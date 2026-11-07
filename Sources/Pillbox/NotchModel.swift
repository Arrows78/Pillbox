import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, music, timer, notes, clipboard, shelf, launcher
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .music: "Music"
        case .timer: "Timer"
        case .notes: "Notes"
        case .clipboard: "Clipboard"
        case .shelf: "Shelf"
        case .launcher: "Launcher"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .music: "music.note"
        case .timer: "timer"
        case .notes: "note.text"
        case .clipboard: "doc.on.clipboard"
        case .shelf: "tray.full.fill"
        case .launcher: "square.grid.2x2.fill"
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
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var duration: TimeInterval = 3
}

/// Physical notch (or virtual pill on Macs without one) of the target screen.
struct NotchGeometry {
    var width: CGFloat = 185
    var height: CGFloat = 32
    var screen: NSScreen?

    static func detect() -> NotchGeometry {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            return NotchGeometry(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top, screen: s)
        }
        let s = NSScreen.main ?? screens.first
        let menuBar = s.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 24
        return NotchGeometry(width: CGFloat(UserDefaults.standard.double(forKey: "pillWidth").nonZero ?? 170),
                             height: max(menuBar, 24), screen: s)
    }
}

extension Double { var nonZero: Double? { self == 0 ? nil : self } }

@MainActor
final class NotchModel: ObservableObject {
    static let shared = NotchModel()

    static let windowSize = CGSize(width: 680, height: 250)
    static let expandedSize = CGSize(width: 620, height: 210)
    static let wing: CGFloat = 62

    @Published var expanded = false
    @Published var tab: Tab = .home
    @Published var activity: Activity?
    @Published var geometry = NotchGeometry.detect()
    /// Set while the user keeps the panel open (text fields focused, drag in progress).
    @Published var pinnedOpen = false
    @Published var dropTargeted = false

    private var activityTask: Task<Void, Never>?

    /// Size of the visible black shape for the current state.
    func size(hasWings: Bool) -> CGSize {
        if expanded { return Self.expandedSize }
        if activity != nil { return CGSize(width: max(geometry.width + 150, 330), height: geometry.height + 34) }
        let extra = hasWings ? Self.wing * 2 : 0
        return CGSize(width: geometry.width + extra, height: geometry.height)
    }

    func expand(_ tab: Tab? = nil) {
        if let tab { self.tab = tab }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { expanded = true }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }

    func collapse() {
        pinnedOpen = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { expanded = false }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }

    func toggle() { expanded ? collapse() : expand() }

    func show(_ activity: Activity) {
        activityTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { self.activity = activity }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        activityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(activity.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismissActivity()
        }
    }

    func dismissActivity() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { activity = nil }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }
}

extension Notification.Name {
    static let notchStateChanged = Notification.Name("pillbox.notchStateChanged")
}

enum Store {
    static let dir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pillbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        if let d = try? JSONEncoder().encode(value) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }
}
