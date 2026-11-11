import EventKit
import Foundation

struct ReminderItem: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var overdue: Bool { due.map { $0 < Date() } ?? false }
}

/// Apple Reminders through EventKit: shows what is open and adds reminders from one line of text.
@MainActor
final class RemindersService: ObservableObject {
    static let shared = RemindersService()
    @Published private(set) var items: [ReminderItem] = []
    @Published var draft = ""
    private let store = EKEventStore()

    var authorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    private var observing = false
    private var watchdog: Timer?

    /// Starts once access exists, and only once. It never prompts.
    func start() {
        guard !observing, authorized else { return }
        observing = true
        watchdog?.invalidate(); watchdog = nil   // access is here, so the timer has nothing left to do
        refresh()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Called at launch. A timer picks up access granted later in System Settings.
    func watch() {
        start()
        guard !observing, watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    func requestAccess() {
        store.requestFullAccessToReminders { [weak self] ok, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { if ok { self?.start() } } }
        }
    }

    func refresh() {
        guard authorized else { items = []; return }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: pred) { found in
            let list = (found ?? []).map { r in
                ReminderItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
            }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.items = list } }
        }
    }

    /// "call mum tomorrow at 9am" becomes the title "call mum" due tomorrow at 9:00.
    nonisolated static func parse(_ text: String, now: Date = Date()) -> (title: String, due: Date?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.matches(in: t, range: NSRange(t.startIndex..., in: t)).last, let date = m.date, let r = Range(m.range, in: t) else { return (t, nil) }
        var title = t.replacingCharacters(in: r, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in [" at", " on", " by", " for", " à", " le"] where title.lowercased().hasSuffix(lead) { title = String(title.dropLast(lead.count)) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? t : title, date)
    }

    func add() {
        let (title, due) = Self.parse(draft)
        guard !title.isEmpty else { return }
        guard authorized else { fail(L("Reminders access is off")); return }
        guard let cal = store.defaultCalendarForNewReminders() else { fail(L("There is no default list for new reminders")); return }
        let r = EKReminder(eventStore: store)
        r.title = title; r.calendar = cal
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        do { try store.save(r, commit: true); draft = ""; refresh() }
        catch { fail(L("Could not save the reminder")) }
    }

    /// The row leaves the list only once EventKit has saved the completion; otherwise the next refresh would bring it back.
    func complete(_ item: ReminderItem) {
        guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted = true
        do { try store.save(r, commit: true); items.removeAll { $0.id == item.id } }
        catch { fail(L("Could not complete the reminder")) }
    }

    private func fail(_ title: String) {
        NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: title, tint: .orange))
    }
}
