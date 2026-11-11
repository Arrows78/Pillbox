import AppKit
import Foundation
import SwiftUI
import EventKit
import Combine

/// Why a new event was not saved; `message` is the text shown to the person.
enum CalendarAddError: Error, Equatable {
    case accessNeeded, saveFailed

    var message: String { self == .accessNeeded ? localized("Calendar access needed") : localized("Could not add the event") }
}

extension CalendarService {
    /// Events from the start of today to the end of the seventh day, all-day ones first. The Calendar tab shows
    /// today and tomorrow or the whole week from this list.
    func agenda(calendars: [EKCalendar]? = nil) -> [AgendaEvent] {
        let cal = Calendar.current, start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 7, to: start) else { return [] }
        let store = CalendarService.eventStore
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
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var next: (title: String, start: Date, end: Date)?
    /// One event store for the whole app: EventKit caches per store, so a second one sees stale data.
    static let eventStore = EKEventStore()
    private var store: EKEventStore { CalendarService.eventStore }
    private var timer: Timer?
    private var watchdog: Timer?

    /// Asks for access (the Allow buttons), with the system prompt when there is one.
    func start() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.begin() } }
        }
    }

    /// Called at launch. It never prompts, and a timer picks up access granted later in System Settings.
    func watch() {
        begin()
        guard timer == nil, watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.begin() }
        }
    }

    /// Starts the refresh once access exists, and only once.
    private func begin() {
        guard timer == nil, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        refresh()
        AgendaModel.shared.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The refresh timer now runs, so the watchdog has nothing left to do.
        watchdog?.invalidate(); watchdog = nil
    }

    /// Saves an event to the default calendar and shows it on the island. Throws when Calendars access is missing or the save fails.
    func createEvent(title: String, start: Date, duration: TimeInterval = 3600) throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let cal = store.defaultCalendarForNewEvents else { throw CalendarAddError.accessNeeded }
        let event = EKEvent(eventStore: store)
        event.title = title; event.calendar = cal
        event.startDate = start
        event.endDate = start.addingTimeInterval(duration)
        do { try store.save(event, span: .thisEvent) } catch { throw CalendarAddError.saveFailed }
        refresh()
        AgendaModel.shared.refresh()
        NotchModel.shared.show(Activity(symbol: "calendar.badge.plus", title: localized("Event added"), subtitle: title, tint: .green))
    }

    /// Adds a one-hour event (starting at the next full hour when no time was given) for the command palette.
    func addEvent(title: String, start: Date?) {
        do {
            try createEvent(title: title, start: start ?? AgendaGrouping.nextHour(after: Date()))
        } catch {
            let failure = error as? CalendarAddError ?? .saveFailed
            let access = failure == .accessNeeded
            NotchModel.shared.show(Activity(symbol: access ? "calendar.badge.exclamationmark" : "exclamationmark.triangle", title: failure.message,
                                            subtitle: access ? localized("Allow it in Settings › Permissions") : nil, tint: .orange))
        }
    }

    func refresh() {
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(86400), calendars: CalendarChoice.visible(in: store))
        let soonest = store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.first
        next = soonest.map { ($0.title ?? localized("Event"), $0.startDate, $0.endDate) }
    }
}
