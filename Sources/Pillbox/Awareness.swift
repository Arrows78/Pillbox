import AppKit
import SwiftUI

// MARK: Block distracting apps during focus

/// Apps (bundle identifiers) hidden while a Focus session runs.
@MainActor
final class BlockedAppsStore: ObservableObject {
    static let shared = BlockedAppsStore()
    @Published var ids: [String] = Store.load("blockedApps.json", as: [String].self) ?? []

    func add() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        guard p.runModal() == .OK else { return }
        for u in p.urls {
            guard let id = Bundle(url: u)?.bundleIdentifier, id != Bundle.main.bundleIdentifier, !ids.contains(id) else { continue }
            ids.append(id)
        }
        save()
    }
    func remove(_ id: String) { ids.removeAll { $0 == id }; save() }
    private func save() { Store.save(ids, "blockedApps.json") }

    static func name(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }
    /// A small sRGB bitmap of an app icon, so the island draws it like any picture.
    static func bitmap(_ icon: NSImage?, side: Int = 48) -> NSImage? {
        guard let icon, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: side, height: side)); img.addRepresentation(rep)
        return img
    }
    static func icon(_ id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Hides a blocked app as soon as it launches or comes to the front while a Focus timer runs. Breaks, countdowns and the stopwatch never block.
@MainActor
final class FocusGuard {
    static let shared = FocusGuard()
    static let allowance: TimeInterval = 5 * 60
    private var allowedUntil: [String: Date] = [:]
    private var lastIsland: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []

    nonisolated static func shouldBlock(bundleID: String?, blocked: Set<String>, mode: TimerService.Mode, running: Bool,
                                        allowedUntil: [String: Date], now: Date) -> Bool {
        guard let id = bundleID, running, mode == .focus, blocked.contains(id) else { return false }
        return (allowedUntil[id] ?? .distantPast) <= now
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for (name, launched) in [(NSWorkspace.didLaunchApplicationNotification, true), (NSWorkspace.didActivateApplicationNotification, false)] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { n in
                guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { FocusGuard.shared.check(app, launched: launched) }
            })
        }
    }

    private func check(_ app: NSRunningApplication, launched: Bool) {
        let t = TimerService.shared
        guard UserDefaults.standard.bool(forKey: "focusBlocking"),
              Self.shouldBlock(bundleID: app.bundleIdentifier, blocked: Set(BlockedAppsStore.shared.ids), mode: t.mode, running: t.running,
                               allowedUntil: allowedUntil, now: Date()), let id = app.bundleIdentifier else { return }
        app.hide()
        // A launching app may not accept hide() until it has finished launching.
        if launched { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { if self.isBlocked(app) { app.hide() } } } }
        if let last = lastIsland[id], Date().timeIntervalSince(last) < 3 { return }
        lastIsland[id] = Date()
        NotchModel.shared.show(Activity(symbol: "hand.raised.fill", title: L("Blocked while focusing"), subtitle: app.localizedName ?? BlockedAppsStore.name(id),
                                        tint: .orange, image: BlockedAppsStore.bitmap(app.icon), actionTitle: L("Allow 5 min"), action: { [weak self] in
            self?.allowedUntil[id] = Date().addingTimeInterval(Self.allowance)
            app.unhide(); app.activate()
        }, duration: 4))
    }

    private func isBlocked(_ app: NSRunningApplication) -> Bool {
        let t = TimerService.shared
        return Self.shouldBlock(bundleID: app.bundleIdentifier, blocked: Set(BlockedAppsStore.shared.ids), mode: t.mode, running: t.running, allowedUntil: allowedUntil, now: Date())
    }
}

// MARK: Space name island

/// The current desktop through the private CGS API, looked up with dlsym: when a symbol is missing the island just never shows.
enum SpaceInfo {
    enum Kind: Equatable { case desktop(Int), fullScreen(String?) }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias CopyFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias ActiveFn = @convention(c) (Int32) -> UInt64
    /// CoreGraphics first, then SkyLight: newer macOS releases moved these symbols there.
    private static let handles: [UnsafeMutableRawPointer] = {
        let paths: [String] = ["/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                               "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        return paths.compactMap { dlopen($0, RTLD_LAZY) }
    }()
    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? { handles.lazy.compactMap { dlsym($0, name) }.first }

    /// Spaces of each display and the active space id, or nil when the API is unavailable.
    static func read() -> (displays: [[String: Any]], active: UInt64)? {
        guard let c = symbol("CGSMainConnectionID"), let s = symbol("CGSCopyManagedDisplaySpaces"), let a = symbol("CGSGetActiveSpace") else { return nil }
        let cid = unsafeBitCast(c, to: ConnFn.self)()
        guard let arr = unsafeBitCast(s, to: CopyFn.self)(cid)?.takeRetainedValue() as? [[String: Any]] else { return nil }
        return (arr, unsafeBitCast(a, to: ActiveFn.self)(cid))
    }

    private static func id(_ d: [String: Any]) -> UInt64? { (d["ManagedSpaceID"] as? NSNumber ?? d["id64"] as? NSNumber)?.uint64Value }

    /// Desktops are numbered per display, like Mission Control; full-screen spaces (type 4) are named after their app.
    static func kind(displays: [[String: Any]], active: UInt64) -> Kind? {
        for d in displays {
            guard let spaces = d["Spaces"] as? [[String: Any]], let space = spaces.first(where: { id($0) == active }) else { continue }
            if (space["type"] as? NSNumber)?.intValue == 4 {
                let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]]
                return .fullScreen(tiles?.compactMap { $0["appName"] as? String }.first)
            }
            let desktops = spaces.filter { ($0["type"] as? NSNumber)?.intValue != 4 }
            return desktops.firstIndex(where: { id($0) == active }).map { .desktop($0 + 1) }
        }
        return nil
    }

    static func label(_ k: Kind, frontApp: String?) -> String {
        switch k {
        case .desktop(let n): L("Desktop %d", n)
        case .fullScreen(let app): app ?? frontApp ?? L("Full screen")
        }
    }
}

@MainActor
final class SpaceWatcher {
    static let shared = SpaceWatcher()
    static let symbol = "rectangle.on.rectangle"
    private var last: UInt64?
    private var observer: NSObjectProtocol?

    func start() {
        last = SpaceInfo.read()?.active
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            // The front app of a full-screen space settles a moment after the switch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { SpaceWatcher.shared.changed() } }
        }
    }

    private func changed() {
        guard let info = SpaceInfo.read() else { return }
        defer { last = info.active }
        guard UserDefaults.standard.bool(forKey: "spaceIsland"), info.active != last, let k = SpaceInfo.kind(displays: info.displays, active: info.active) else { return }
        let m = NotchModel.shared
        if m.activity?.symbol == Self.symbol { m.dismissActivity() }   // quick switches replace the label instead of queueing
        m.show(Activity(symbol: Self.symbol, title: SpaceInfo.label(k, frontApp: NSWorkspace.shared.frontmostApplication?.localizedName), tint: .cyan, duration: 1.3))
    }
}

// MARK: Camera guard

/// An island the moment the camera turns on. macOS does not say which app opened it: the front app is a best guess,
/// shown as such, and nothing is shown for Pillbox's own mirror.
enum CameraGuard {
    /// nil: no island. Otherwise the probable app, if any.
    static func island(mirrorOpen: Bool, frontName: String?, frontBundle: String?, own: String?) -> String?? {
        if mirrorOpen { return nil }
        return .some(frontBundle == own ? nil : frontName)
    }

    @MainActor static func cameraStarted() {
        let front = NSWorkspace.shared.frontmostApplication
        guard let app = island(mirrorOpen: CameraMirror.shared.isOpen, frontName: front?.localizedName, frontBundle: front?.bundleIdentifier, own: Bundle.main.bundleIdentifier) else { return }
        NotchModel.shared.show(Activity(symbol: "video.fill", title: L("Camera turned on"), subtitle: app.map { L("Probably %@", $0) }, tint: .green,
                                        image: app == nil ? nil : BlockedAppsStore.bitmap(front?.icon), duration: 4))
    }
}

// MARK: Settings

struct AwarenessSettings: View {
    @AppStorage("focusBlocking") private var focusBlocking = false
    @AppStorage("spaceIsland") private var spaceIsland = false
    @AppStorage("cameraGuard") private var cameraGuard = false
    @ObservedObject private var blocked = BlockedAppsStore.shared

    var body: some View {
        SettingsCard(title: "Focus") {
            SettingsToggle("Block distracting apps during focus", "While a Focus timer runs, these apps are hidden as soon as they open.", isOn: $focusBlocking)
            if focusBlocking {
                ForEach(blocked.ids, id: \.self) { id in
                    SettingsRow(title: LocalizedStringKey(BlockedAppsStore.name(id))) {
                        HStack(spacing: 8) {
                            if let i = BlockedAppsStore.icon(id) { Image(nsImage: i).resizable().frame(width: 18, height: 18) }
                            Button("Remove") { blocked.remove(id) }.controlSize(.small)
                        }
                    }
                }
                SettingsRow(title: "Blocked apps", subtitle: blocked.ids.isEmpty ? "No app yet" : nil) { Button("Add app…") { blocked.add() }.controlSize(.small) }
            }
        }
        SettingsCard(title: "Awareness") {
            SettingsToggle("Desktop name island", "Shows the desktop number, or the app in full screen, when you switch Spaces.", isOn: $spaceIsland)
            SettingsToggle("Camera island", "Shows when an app turns the camera on, with the app in front as the likely one.", isOn: $cameraGuard)
        }
    }
}
