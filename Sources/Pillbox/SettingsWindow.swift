import Foundation
import AppKit
import SwiftUI
import ServiceManagement

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    /// Tells an open settings window to show another pane; its object is the SettingsPane.
    static let paneRequest = Notification.Name("PillboxSettingsPaneRequest")

    /// Opens the window on `pane`. An open window switches to a pane that is asked for; without one it stays where it is.
    static func show(pane: SettingsPane? = nil) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(pane: pane ?? .general)))
            w.title = "Pillbox Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.backgroundColor = SettingsStyle.window
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            window = w
        } else if let pane {
            NotificationCenter.default.post(name: paneRequest, object: pane)
        }
        applyTheme()
        NSApp.activate(ignoringOtherApps: true)
        if let window { placeInMiddle(window); window.makeKeyAndOrderFront(nil) }
    }

    /// Centres the window on the main screen's visible area, below the menu bar and the island, and shrinks it to fit.
    /// `center()` alone keeps the window's own height, which can put its top under the island.
    static func placeInMiddle(_ w: NSWindow) {
        guard let vis = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { w.center(); return }
        var f = w.frame
        f.size.width = min(f.width, vis.width - 40)
        f.size.height = min(f.height, vis.height - 80)
        f.origin = CGPoint(x: vis.midX - f.width / 2, y: vis.midY - f.height / 2)
        w.setFrame(f, display: true)
    }

    /// The theme chosen in General applies to this window only: the island stays dark, other windows follow macOS.
    static func applyTheme() {
        window?.appearance = SettingsStyle.appearance(for: UserDefaults.standard.string(forKey: "appearance"))
    }
}
