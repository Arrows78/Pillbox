import Foundation
import AppKit
import SwiftUI

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
    /// Kept for existing callers; the helper lives in AppIconImage.
    static func bitmap(_ icon: NSImage?, side: Int = 48) -> NSImage? { AppIconImage.bitmap(icon, side: side) }
    static func icon(_ id: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// Icons for the islands.
enum AppIconImage {
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
        guard Preferences.focusBlocking.value,
              Self.shouldBlock(bundleID: app.bundleIdentifier, blocked: Set(BlockedAppsStore.shared.ids), mode: t.mode, running: t.running,
                               allowedUntil: allowedUntil, now: Date()), let id = app.bundleIdentifier else { return }
        app.hide()
        // A launching app may not accept hide() until it has finished launching.
        if launched { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { if self.isBlocked(app) { app.hide() } } } }
        if let last = lastIsland[id], Date().timeIntervalSince(last) < 3 { return }
        lastIsland[id] = Date()
        NotchModel.shared.show(Activity(symbol: "hand.raised.fill", title: localized("Blocked while focusing"), subtitle: app.localizedName ?? BlockedAppsStore.name(id),
                                        tint: .orange, image: AppIconImage.bitmap(app.icon), actionTitle: localized("Allow %d min", Int(Self.allowance / 60)), action: { [weak self] in
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

struct AwarenessSettings: View {
    @AppStorage(Preferences.focusBlocking.key) private var focusBlocking = Preferences.focusBlocking.defaultValue
    @AppStorage(Preferences.spaceIsland.key) private var spaceIsland = Preferences.spaceIsland.defaultValue
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
