import Foundation
import AppKit
import SwiftUI

/// Paints the top strip of the screen black, behind the menu bar items, so the notch disappears into it.
@MainActor
final class NotchHider {
    static let shared = NotchHider()
    private var window: NSWindow?

    func apply(screen: NSScreen?, height: CGFloat) {
        guard UserDefaults.standard.bool(forKey: "hideNotch"), let screen else { window?.orderOut(nil); window = nil; return }
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let w = window ?? {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black; w.isOpaque = true; w.hasShadow = false; w.ignoresMouseEvents = true; w.isReleasedWhenClosed = false
            // Above the wallpaper and desktop icons, below every app window and the menu bar itself.
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window = w; return w
        }()
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
    }
}
