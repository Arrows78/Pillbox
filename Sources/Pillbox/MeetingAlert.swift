import AppKit
import Foundation

/// Which timed event the island announces before it starts.
enum MeetingAlertRule {
    static let key = "meetingAlertMinutes"
    /// The lead times Settings offers, in minutes; 0 (Off) is the default.
    static let minutes = [5, 10, 15]

    /// The soonest timed event that starts within `lead` minutes after `now`, not yet announced. Nil when `lead` is 0.
    static func next(in events: [AgendaEvent], now: Date, lead: Int, announced: Set<String>) -> AgendaEvent? {
        guard lead > 0 else { return nil }
        let limit = now.addingTimeInterval(TimeInterval(lead * 60))
        return events.filter { !$0.allDay && $0.start > now && $0.start <= limit && !announced.contains($0.id) }
            .min { $0.start < $1.start }
    }
}

/// Shows "Meeting in N min" on the island once per event. The announced IDs live in memory only, so a restart can announce again.
@MainActor
final class MeetingAlert {
    static let shared = MeetingAlert()
    /// Announced event IDs with their start. Entries that started more than a day ago are dropped.
    private var announced: [String: Date] = [:]
    private var timer: Timer?

    /// Re-reads the agenda every minute, so an event that comes near is seen even when nothing else changed.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { if Preferences.meetingAlert.value > 0 { AgendaModel.shared.refresh() } }
        }
    }

    /// Called after every agenda refresh. Announces at most one event per call.
    func check(_ events: [AgendaEvent], now: Date = Date()) {
        announced = announced.filter { $0.value > now.addingTimeInterval(-86400) }
        guard let event = MeetingAlertRule.next(in: events, now: now, lead: Preferences.meetingAlert.value, announced: Set(announced.keys)) else { return }
        announced[event.id] = event.start
        let minutes = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        var activity = Activity(symbol: "calendar.badge.clock", title: localized("Meeting in %d min", minutes), subtitle: event.title,
                                tint: event.color, duration: 8)
        if let url = event.join {
            activity.actionTitle = localized("Join")
            activity.action = { NSWorkspace.shared.open(url) }
        }
        NotchModel.shared.show(activity)
    }
}
