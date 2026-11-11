import Foundation
import AppKit
import SwiftUI

/// Hides the mouse pointer after a few seconds without movement, in every app (films, presentations). Any movement brings it back.
/// The connection property is a private CGS call looked up with dlsym: when it is missing, only Pillbox's own windows would hide it, so it stays off.
@MainActor
final class PointerHider {
    static let shared = PointerHider()
    nonisolated static let key = "hidePointerAfter"
    private var timer: Timer?
    private var monitor: Any?
    private var hidden = false
    private var warned = false
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private static let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

    private static func allowInBackground() -> Bool {
        guard let h = handle, let c = dlsym(h, "CGSMainConnectionID"), let s = dlsym(h, "CGSSetConnectionProperty") else { return false }
        let cid = unsafeBitCast(c, to: ConnFn.self)()
        return unsafeBitCast(s, to: SetFn.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue) == 0
    }

    func apply() {
        let seconds = UserDefaults.standard.integer(forKey: Self.key)
        if seconds > 0, timer == nil {
            guard Self.allowInBackground() else {
                // The private symbols are missing on this macOS: say so once instead of doing nothing.
                if !warned { warned = true; NotchModel.shared.show(Activity(symbol: "cursorarrow.slash", title: localized("Hiding the pointer is not supported on this Mac"), tint: .orange)) }
                return
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { PointerHider.shared.tick() } }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .scrollWheel]) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { PointerHider.shared.show() } }
            }
        } else if seconds == 0, timer != nil {
            timer?.invalidate(); timer = nil
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            show()
        }
    }

    private func tick() {
        let seconds = UserDefaults.standard.integer(forKey: Self.key)
        guard seconds > 0, !hidden else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        // Not while the island is open, a drag is in progress or the pointer rests on a Pillbox window.
        if idle >= Double(seconds), !NotchModel.shared.expanded, NSEvent.pressedMouseButtons == 0 { CGDisplayHideCursor(CGMainDisplayID()); hidden = true }
    }

    private func show() { if hidden { CGDisplayShowCursor(CGMainDisplayID()); hidden = false } }
}

// MARK: Hide while the screen is mirrored
