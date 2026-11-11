import SwiftUI
import EventKit
import Combine

struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let calendar: String
    let color: Color
    let join: URL?
}

/// One day of the agenda: its offset from today (0 is today) and the events that overlap it, all-day ones first.
struct AgendaDay: Equatable {
    let offset: Int
    let start: Date
    let events: [AgendaEvent]
}

/// Pure date helpers behind the Calendar tab, so the grouping can be tested without EventKit.
enum AgendaGrouping {
    /// The `count` days from the start of `now`'s day. An event belongs to every day it overlaps, so a
    /// multi-day event shows on each of its days and one that is still running counts as today.
    static func days(_ events: [AgendaEvent], count: Int, now: Date, calendar: Calendar = .current) -> [AgendaDay] {
        let first = calendar.startOfDay(for: now)
        return (0..<max(count, 0)).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: first),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let rows = events.filter { $0.start < dayEnd && ($0.end > dayStart || $0.start >= dayStart) }
                .sorted { ($0.allDay ? 0 : 1, $0.start, $0.title) < ($1.allDay ? 0 : 1, $1.start, $1.title) }
            return AgendaDay(offset: offset, start: dayStart, events: rows)
        }
    }

    /// The day of `day` at the hour and minute of `time`.
    static func combine(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    /// The next full hour after `date`: the default start of a new event.
    static func nextHour(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? date
    }
}

/// Finds the link that joins a video call in an event's URL, location or notes.
enum MeetingLink {
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "facetime.apple.com", "gotomeeting.com"]

    static func find(in texts: [String?]) -> URL? {
        for t in texts.compactMap({ $0 }) {
            let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            for m in det?.matches(in: t, range: NSRange(t.startIndex..., in: t)) ?? [] {
                if let u = m.url, let h = u.host?.lowercased(), u.scheme?.hasPrefix("http") == true,
                   hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return u }
            }
        }
        return nil
    }
}

@MainActor
final class AgendaModel: ObservableObject {
    static let shared = AgendaModel()
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var denied = false
    private var observer: NSObjectProtocol?
    private var feedChanges: AnyCancellable?

    func refresh() {
        denied = EKEventStore.authorizationStatus(for: .event) != .fullAccess && ICSFeeds.shared.feeds.isEmpty
        let own = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? CalendarService.shared.agenda() : []
        events = (own + ICSFeeds.shared.events).sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
        MeetingAlert.shared.check(events)
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        // Adding or removing a feed changes the events too, not only the next fetch.
        if feedChanges == nil {
            feedChanges = ICSFeeds.shared.$feeds.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
}

struct CalendarTab: View {
    @ObservedObject var model = AgendaModel.shared
    @ObservedObject var feeds = ICSFeeds.shared
    /// Today and tomorrow, or the seven days of the week.
    @State private var week = false
    @State private var adding = false
    /// The calendars the menu shows; the same set Settings edits (CalendarChoice.hiddenKey).
    @State private var hidden = CalendarChoice.hidden

    private var days: [AgendaDay] {
        AgendaGrouping.days(model.events, count: week ? 7 : 2, now: Date()).filter { !$0.events.isEmpty }
    }

    var body: some View {
        Group {
            if model.denied {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                    Text("Calendar access is off").foregroundStyle(.secondary)
                    Button("Allow Calendar Access") { PermissionsCenter.shared.request(.calendar) }.buttonStyle(PillButtonStyle(tint: .red))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    header
                    if adding {
                        NewEventForm { adding = false }
                    } else if days.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                            Text(week ? "No events this week" : "No events today or tomorrow").foregroundStyle(.secondary)
                            if !feeds.failed.isEmpty {
                                Text("Some calendar links could not be loaded").font(Design.label).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(days, id: \.offset) { day in
                                    Text(verbatim: dayTitle(day)).font(Design.labelStrong).foregroundStyle(.white.opacity(0.5))
                                    ForEach(day.events) { row($0) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .onAppear { model.refresh(); hidden = CalendarChoice.hidden }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $week) {
                Text("Two days").tag(false)
                Text("Week").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            Spacer()
            if EKEventStore.authorizationStatus(for: .event) == .fullAccess { calendarMenu }
            if !adding { Button("New event") { adding = true }.buttonStyle(PillButtonStyle()) }
        }.controlSize(.small)
    }

    /// Checkmarks for the macOS calendars that feed this tab.
    private var calendarMenu: some View {
        Menu {
            ForEach(CalendarService.eventStore.calendars(for: .event).sorted { $0.title < $1.title }, id: \.calendarIdentifier) { c in
                Toggle(isOn: visibility(c.calendarIdentifier)) { Text(verbatim: c.title) }
            }
        } label: {
            Label("Calendars", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func visibility(_ id: String) -> Binding<Bool> {
        Binding(get: { !hidden.contains(id) }, set: { on in
            if on { hidden.remove(id) } else { hidden.insert(id) }
            UserDefaults.standard.set(Array(hidden).sorted(), forKey: CalendarChoice.hiddenKey)
            CalendarService.shared.refresh(); AgendaModel.shared.refresh()
        })
    }

    private func dayTitle(_ day: AgendaDay) -> String {
        switch day.offset {
        case 0: return localized("Today")
        case 1: return localized("Tomorrow")
        default: return day.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    private func row(_ e: AgendaEvent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: e.title).font(Design.bodyMedium).lineLimit(1)
                Text(verbatim: e.allDay ? localized("All day") : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                    .font(Design.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = e.join, e.end > Date() {
                Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }.buttonStyle(PillButtonStyle(tint: .green))
            }
        }
        .opacity(e.end < Date() && !e.allDay ? 0.4 : 1)
        .padding(8).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Design.tileRadius))
    }
}

/// Title, day, start time and length of a new event, saved to the default calendar. A failure stays on the form.
struct NewEventForm: View {
    var onDone: () -> Void
    @State private var title = ""
    @State private var day = Date()
    @State private var time = AgendaGrouping.nextHour(after: Date())
    @State private var minutes = 60
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Event title", text: $title).textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                DatePicker("", selection: $day, displayedComponents: .date).labelsHidden()
                Text("Start").font(Design.label).foregroundStyle(.secondary)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack(spacing: 8) {
                Picker("", selection: $minutes) {
                    Text(localized("%d min", 30)).tag(30)
                    Text(localized("%d min", 60)).tag(60)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
                Spacer()
                Button("Cancel") { onDone() }.buttonStyle(PillButtonStyle())
                Button("Add") { add() }.buttonStyle(PillButtonStyle(tint: .green))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let message = error {
                Text(message).font(Design.label).foregroundStyle(.orange)
            }
        }
        .controlSize(.small)
    }

    private func add() {
        let name = title.trimmingCharacters(in: .whitespaces)
        do {
            try CalendarService.shared.createEvent(title: name, start: AgendaGrouping.combine(day: day, time: time), duration: TimeInterval(minutes * 60))
            onDone()
        } catch {
            self.error = (error as? CalendarAddError ?? .saveFailed).message
        }
    }
}
