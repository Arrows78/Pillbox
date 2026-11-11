import AppKit
import EventKit
import SwiftUI

// MARK: Calendar subscriptions (.ics links) and calendar selection

struct ICSFeed: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

/// A small iCalendar reader: enough for the private links calendars hand out (Google, Notion, Luma, Outlook).
/// Recurring events appear only when the feed expands them; RRULE itself is not evaluated.
enum ICSParser {
    struct Event: Equatable { var uid: String; var title: String; var start: Date; var end: Date; var allDay: Bool; var location: String?; var url: String?; var notes: String? }

    /// Folded lines are joined (a line starting with a space or tab continues the previous one).
    static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !out.isEmpty { out[out.count - 1] += line.dropFirst() } else if !line.isEmpty { out.append(line) }
        }
        return out
    }

    /// "DTSTART;TZID=Europe/Paris:20260211T090000" → (name, parameters, value).
    static func split(_ line: String) -> (name: String, params: [String: String], value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = line[..<colon].split(separator: ";").map(String.init)
        guard let name = head.first?.uppercased() else { return nil }
        var params: [String: String] = [:]
        for p in head.dropFirst() { let kv = p.split(separator: "=", maxSplits: 1).map(String.init); if kv.count == 2 { params[kv[0].uppercased()] = kv[1] } }
        return (name, params, String(line[line.index(after: colon)...]))
    }

    /// 20260211T090000Z, 20260211T090000 (in TZID or local time) or 20260211 (a date).
    static func date(_ value: String, tzid: String?) -> (Date, Bool)? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        if value.count == 8 {
            f.dateFormat = "yyyyMMdd"; f.timeZone = .current
            return f.date(from: value).map { ($0, true) }
        }
        let utc = value.hasSuffix("Z")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = utc ? TimeZone(identifier: "UTC") : tzid.flatMap { TimeZone(identifier: $0) } ?? .current
        return f.date(from: utc ? String(value.dropLast()) : value).map { ($0, false) }
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func parse(_ text: String) -> [Event] {
        var out: [Event] = []
        var cur: [String: (params: [String: String], value: String)]?
        for line in unfold(text) {
            if line.uppercased() == "BEGIN:VEVENT" { cur = [:]; continue }
            if line.uppercased() == "END:VEVENT" {
                defer { cur = nil }
                guard let c = cur, let s = c["DTSTART"], let (start, allDay) = date(s.value, tzid: s.params["TZID"]) else { continue }
                let end = c["DTEND"].flatMap { date($0.value, tzid: $0.params["TZID"])?.0 } ?? (allDay ? start.addingTimeInterval(86400) : start.addingTimeInterval(3600))
                out.append(Event(uid: c["UID"]?.value ?? "\(start.timeIntervalSince1970)", title: c["SUMMARY"].map { unescape($0.value) } ?? "Event", start: start, end: end, allDay: allDay,
                                 location: c["LOCATION"].map { unescape($0.value) }, url: c["URL"]?.value, notes: c["DESCRIPTION"].map { unescape($0.value) }))
                continue
            }
            guard cur != nil, let (name, params, value) = split(line) else { continue }
            cur?[name] = (params, value)
        }
        return out
    }
}

@MainActor
final class ICSFeeds: ObservableObject {
    static let shared = ICSFeeds()
    static let file = "icsFeeds.json"
    @Published var feeds: [ICSFeed] = Store.load(ICSFeeds.file, as: [ICSFeed].self) ?? [] { didSet { Store.save(feeds, Self.file); schedule() } }
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var failed: Set<UUID> = []
    private var timer: Timer?
    private var fetched: [UUID: [ICSParser.Event]] = [:]

    /// webcal:// links are plain https.
    nonisolated static func url(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("webcal://") { t = "https://" + t.dropFirst(9) }
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme), u.host != nil else { return nil }
        return u
    }

    func add(name: String, url: String) -> Bool {
        guard Self.url(url) != nil else { return false }
        let n = name.trimmingCharacters(in: .whitespaces)
        feeds.append(ICSFeed(name: n.isEmpty ? (Self.url(url)?.host ?? "Calendar") : n, url: url.trimmingCharacters(in: .whitespaces)))
        return true
    }
    func remove(_ f: ICSFeed) { feeds.removeAll { $0.id == f.id }; fetched[f.id] = nil; rebuild() }

    func start() { schedule(); refresh() }

    private func schedule() {
        timer?.invalidate()
        guard !feeds.isEmpty else { events = []; return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        refresh()
    }

    func refresh() {
        for f in feeds {
            guard let u = Self.url(f.url) else { continue }
            var req = URLRequest(url: u); req.timeoutInterval = 20
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? (data != nil)
                let parsed = ok ? data.map { ICSParser.parse(String(decoding: $0, as: UTF8.self)) } : nil
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let parsed { self.fetched[f.id] = parsed; self.failed.remove(f.id) } else { self.failed.insert(f.id) }
                        self.rebuild()
                    }
                }
            }.resume()
        }
    }

    /// Today's and tomorrow's events of every feed, as agenda rows (teal, so they stand apart from macOS calendars).
    private func rebuild() {
        let cal = Calendar.current, start = cal.startOfDay(for: Date()), end = cal.date(byAdding: .day, value: 2, to: start) ?? start
        var out: [AgendaEvent] = []
        for f in feeds {
            for e in fetched[f.id] ?? [] where e.end > start && e.start < end {
                out.append(AgendaEvent(id: "ics-\(f.id)-\(e.uid)-\(e.start.timeIntervalSince1970)", title: e.title, start: e.start, end: e.end, allDay: e.allDay,
                                       calendar: f.name, color: .teal, join: MeetingLink.find(in: [e.url, e.location, e.notes])))
            }
        }
        events = out
        AgendaModel.shared.refresh()
    }
}

/// Which macOS calendars feed the Home card, the Calendar tab and the menu bar: all of them unless turned off here.
enum CalendarChoice {
    static let hiddenKey = "hiddenCalendars"
    static var hidden: Set<String> { Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []) }
    static func visible(in store: EKEventStore) -> [EKCalendar]? {
        let h = hidden
        guard !h.isEmpty else { return nil }
        return store.calendars(for: .event).filter { !h.contains($0.calendarIdentifier) }
    }
}

/// Settings › General › Calendars: the macOS calendars to show and the .ics subscriptions.
struct CalendarsSettings: View {
    @ObservedObject var feeds = ICSFeeds.shared
    @State private var hidden = CalendarChoice.hidden
    @State private var name = ""
    @State private var link = ""
    @State private var invalid = false
    private let store = EKEventStore()

    var body: some View {
        SettingsCard(title: "Calendars") {
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                let cals = store.calendars(for: .event).sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
                ForEach(cals, id: \.calendarIdentifier) { c in
                    SettingsRow(title: LocalizedStringKey(c.title), subtitle: LocalizedStringKey(c.source.title)) {
                        Toggle("", isOn: Binding(get: { !hidden.contains(c.calendarIdentifier) }, set: { on in
                            if on { hidden.remove(c.calendarIdentifier) } else { hidden.insert(c.calendarIdentifier) }
                            UserDefaults.standard.set(Array(hidden).sorted(), forKey: CalendarChoice.hiddenKey)
                            CalendarService.shared.refresh(); AgendaModel.shared.refresh()
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(SettingsStyle.accent).accessibilityLabel(Text(verbatim: c.title))
                    }
                }
            } else {
                SettingsRow(title: "macOS calendars", subtitle: "Allow Calendars access to choose which ones to show.") {
                    Button("Allow") { PermissionsCenter.shared.request(.calendar) }.controlSize(.small)
                }
            }
        }
        SettingsCard(title: "Calendar subscriptions") {
            ForEach(feeds.feeds) { f in
                SettingsRow(title: LocalizedStringKey(f.name), subtitle: feeds.failed.contains(f.id) ? "Could not load this link" : LocalizedStringKey(f.url)) {
                    Button("Remove") { feeds.remove(f) }.controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    TextField("Name", text: $name).frame(width: 140)
                    TextField("https://… or webcal://… private .ics link", text: $link)
                    Button("Add") { invalid = !feeds.add(name: name, url: link); if !invalid { name = ""; link = "" } }.disabled(link.isEmpty)
                }.controlSize(.small)
                Text(invalid ? "Check the link: it must start with https:// or webcal://" : "The private address of a Google, Notion, Luma or Outlook calendar. Read every 30 minutes; recurring events show only when the feed expands them.")
                    .font(.system(size: 11)).foregroundStyle(invalid ? .orange : SettingsStyle.dim).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
    }
}
