import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, music, timer, stocks, ai, pulls, reminders, notifications, notes, clipboard, shelf, launcher, terminal, prompter, calendar
    var id: String { rawValue }

    /// Tabs the user turned off in Settings › Island, stored as a comma-separated list. Home can never be hidden.
    static let hiddenKey = "hiddenTabs"
    nonisolated static func hidden(from setting: String?) -> Set<Tab> {
        Set((setting ?? "").split(separator: ",").compactMap { Tab(rawValue: String($0)) }).subtracting([.home])
    }
    static var hidden: Set<Tab> { hidden(from: UserDefaults.standard.string(forKey: hiddenKey)) }

    /// The order chosen in Settings › Tabs and menu bar, stored as a comma-separated list.
    static let orderKey = "tabOrder"
    /// Every tab in the stored order. Home always comes first; unknown names are dropped, and a tab the stored list
    /// does not mention yet (a new one) goes after the others in its usual place.
    nonisolated static func ordered(from setting: String?) -> [Tab] {
        var seen: Set<Tab> = [.home]
        let stored = (setting ?? "").split(separator: ",").compactMap { Tab(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return [.home] + stored + allCases.filter { !seen.contains($0) }
    }
    static var ordered: [Tab] { ordered(from: UserDefaults.standard.string(forKey: orderKey)) }
    /// The tabs shown in the bar, in the chosen order: ⌘1–9, swipes, the palette and the menu follow this list.
    static var visible: [Tab] { let h = hidden; return ordered.filter { !h.contains($0) } }
    var title: String {
        switch self {
        case .home: localized("Home")
        case .music: localized("Music")
        case .timer: localized("Timer")
        case .stocks: localized("Stocks")
        case .ai: localized("AI usage")
        case .pulls: localized("Pull requests")
        case .reminders: localized("Reminders")
        case .notifications: localized("Notifications")
        case .notes: localized("Notes")
        case .clipboard: localized("Clipboard")
        case .shelf: localized("Shelf")
        case .launcher: localized("Launcher")
        case .terminal: localized("Terminal")
        case .prompter: localized("Prompter")
        case .calendar: localized("Calendar")
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .ai: "sparkles"
        case .pulls: "arrow.triangle.pull"
        case .reminders: "checklist"
        case .notifications: "bell.badge.fill"
        case .notes: "note.text"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.full.fill"
        case .launcher: "square.grid.2x2.fill"
        case .terminal: "terminal.fill"
        case .prompter: "text.viewfinder"
        case .calendar: "calendar"
        }
    }
}

/// A transient island shown in place of the collapsed pill (battery, download, caps lock...).
struct Activity: Identifiable {
    let id = UUID()
    var symbol: String
    var title: String
    var subtitle: String? = nil
    var tint: Color = .white
    var image: NSImage? = nil   // an app icon drawn instead of the symbol
    var progress: Double? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var duration: TimeInterval = 3
    /// Low: a passing HUD (volume, caps lock) that is dropped rather than queued behind something else.
    /// High: goes to the front of the queue and replaces a HUD on screen (low battery, a call, a code).
    var priority: Priority = .normal
    enum Priority { case low, normal, high }
    /// False for an island shown again from the history, so it is not added a second time.
    var inHistory = true
}

/// A permission request from a coding agent, answered with Allow or Deny.
struct Approval: Identifiable {
    let id = UUID()
    var tool: String
    var detail: String
    var respond: (String) -> Void   // "allow", "deny" or "ask" (hand back to the terminal)
}

/// Physical notch (or virtual pill on Macs without one) of the target screen.
struct NotchGeometry {
    var width: CGFloat = 185
    var height: CGFloat = 32
    var screen: NSScreen?
    /// A hardware notch: the open panel must keep its controls below it, where they can be seen.
    var notch = false

    static func detect() -> NotchGeometry {
        let screens = NSScreen.screens
        let chosen = UserDefaults.standard.string(forKey: "targetDisplay").flatMap { n in screens.first { $0.localizedName == n } }
        if let s = chosen ?? screens.first(where: { $0.safeAreaInsets.top > 0 }), s.safeAreaInsets.top > 0,
           let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return NotchGeometry(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top, screen: s, notch: true)
        }
        let s = chosen ?? NSScreen.main ?? screens.first
        let menuBar = s.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 24
        return NotchGeometry(width: CGFloat(Preferences.pillWidth.value.nonZero ?? Preferences.pillWidth.defaultValue),
                             height: max(menuBar, 24), screen: s)
    }
}

extension Double { var nonZero: Double? { self == 0 ? nil : self } }

@MainActor
final class NotchModel: ObservableObject {
    static let shared = NotchModel()

    static let windowSize = CGSize(width: 1000, height: 480)
    static let expandedSize = CGSize(width: 760, height: 340)
    static let wing: CGFloat = 62

    /// User-chosen scale of the open panel (0.8 to 1.3).
    static var scale: CGFloat { CGFloat(min(max(UserDefaults.standard.object(forKey: "panelScale") as? Double ?? 1, 0.8), 1.3)) }
    /// Every tab opens at the same size, so the panel does not jump when switching tabs.
    static func baseExpanded() -> CGSize { expandedSize }

    @Published var expanded = false
    @Published var tab: Tab = .home
    @Published var activity: Activity?
    @Published var approval: Approval?
    @Published var geometry = NotchGeometry.detect()
    /// Set while the user keeps the panel open (text fields focused, drag in progress).
    @Published var pinnedOpen = false
    @Published var dropTargeted = false

    private var activityTask: Task<Void, Never>?

    /// Size of the visible black shape for the current state.
    func size(hasWings: Bool) -> CGSize {
        if approval != nil { return CGSize(width: 520, height: geometry.height + 92) }
        if expanded { let b = Self.baseExpanded(); return CGSize(width: b.width * Self.scale, height: b.height * Self.scale) }
        if activity != nil || DictationService.shared.active { return CGSize(width: max(geometry.width + 150, 330), height: geometry.height + 34) }
        let extra = hasWings ? Self.wing * 2 : 0
        return CGSize(width: geometry.width + extra, height: geometry.height)
    }

    func expand(_ tab: Tab? = nil) {
        if let tab { self.tab = tab }
        if !expanded { Haptics.tap() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { expanded = true }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }

    func collapse() {
        pinnedOpen = false
        if expanded { Haptics.tap() }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { expanded = false }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }

    func toggle() { expanded ? collapse() : expand() }

    private var queue = ActivityQueue()

    func show(_ activity: Activity) {
        // Volume and brightness can go to a slim bar on the screen edge instead of the island.
        if let p = activity.progress, Preferences.hudStyle.value == "edge" { EdgeHUD.shared.show(symbol: activity.symbol, level: p); return }
        guard queue.push(activity) else { return }
        present()
    }

    /// Shows `queue.current` and arms the timer that moves on to the next one.
    private func present() {
        activityTask?.cancel()
        guard let a = queue.current else { return }
        IslandHistory.shared.record(a)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { self.activity = a }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        activityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(a.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissActivity()
        }
    }

    private var approvalTask: Task<Void, Never>?

    /// Shows an Allow / Deny island. Falls back to "ask" after `timeout` so the agent never hangs.
    func requestApproval(tool: String, detail: String, timeout: TimeInterval = 120, respond: @escaping (String) -> Void) {
        resolveApproval("ask")   // a newer request supersedes the previous one
        approvalTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { approval = Approval(tool: tool, detail: detail, respond: respond) }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        NSSound(named: "Pop")?.play()
        approvalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.resolveApproval("ask")
        }
    }

    func resolveApproval(_ decision: String) {
        guard let a = approval else { return }
        approvalTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { approval = nil }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        a.respond(decision)
    }

    func dismissActivity() {
        queue.advance()
        if queue.current != nil { present(); return }
        activityTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { activity = nil }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }
}

extension Notification.Name {
    static let notchStateChanged = Notification.Name("pillbox.notchStateChanged")
}
