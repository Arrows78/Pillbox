import SwiftUI
import EventKit

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

extension CalendarService {
    /// Events from the start of today to the end of tomorrow, all-day ones first.
    func agenda(calendars: [EKCalendar]? = nil) -> [AgendaEvent] {
        let cal = Calendar.current, start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return [] }
        let store = EKEventStore()
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars ?? CalendarChoice.visible(in: store))
        return store.events(matching: pred)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { e in
                AgendaEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)", title: e.title ?? "Event",
                            start: e.startDate, end: e.endDate, allDay: e.isAllDay, calendar: e.calendar.title,
                            color: Color(nsColor: e.calendar.color ?? .systemRed), join: MeetingLink.find(in: [e.url?.absoluteString, e.location, e.notes]))
            }
    }
}

@MainActor
final class AgendaModel: ObservableObject {
    static let shared = AgendaModel()
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var denied = false
    private var observer: NSObjectProtocol?

    func refresh() {
        denied = EKEventStore.authorizationStatus(for: .event) != .fullAccess && ICSFeeds.shared.feeds.isEmpty
        let own = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? CalendarService.shared.agenda() : []
        events = (own + ICSFeeds.shared.events).sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }
}

struct CalendarTab: View {
    @ObservedObject var model = AgendaModel.shared

    private var days: [(label: String, events: [AgendaEvent])] {
        let cal = Calendar.current
        let today = model.events.filter { cal.isDateInToday($0.start) || ($0.allDay && $0.start <= Date() && $0.end > Date()) }
        let ids = Set(today.map(\.id))
        let rest = model.events.filter { !ids.contains($0.id) }
        return [(L("Today"), today), (L("Tomorrow"), rest)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        Group {
            if model.denied {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                    Text("Calendar access is off").foregroundStyle(.secondary)
                    Button("Allow Calendar Access") { PermissionsCenter.shared.request(.calendar); CalendarService.shared.start() }.buttonStyle(PillButtonStyle(tint: .red))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.events.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                    Text("No events today or tomorrow").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(days, id: \.label) { day in
                            Text(verbatim: day.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                            ForEach(day.events) { row($0) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { model.refresh() }
    }

    private func row(_ e: AgendaEvent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(verbatim: e.allDay ? L("All day") : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if let url = e.join, e.end > Date() {
                Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }.buttonStyle(PillButtonStyle(tint: .green))
            }
        }
        .opacity(e.end < Date() && !e.allDay ? 0.4 : 1)
        .padding(8).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
