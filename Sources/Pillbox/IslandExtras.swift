import AppKit
import SwiftUI

// MARK: Idle pill: clock and battery on the wings when nothing else is live

enum IdlePill {
    static let key = "idleClock"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// The wings of a resting pill: battery on the left, the time on the right.
struct IdleClockWings: View {
    @ObservedObject var battery = BatteryService.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: battery.pluggedIn ? "battery.100percent.bolt" : battery.level <= 20 ? "battery.25percent" : "battery.75percent")
                    .font(.system(size: 10)).foregroundStyle(battery.level <= 20 && !battery.pluggedIn ? .red : .white.opacity(0.8))
                Text(verbatim: "\(battery.level)%").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
            }.frame(width: NotchModel.wing)
            Spacer(minLength: NotchModel.shared.geometry.width)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }.frame(width: NotchModel.wing)
        }
        .frame(maxHeight: NotchModel.shared.geometry.height)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Haptics

/// A light tap of the trackpad when the island opens or closes (opt-in, Settings › Island).
enum Haptics {
    static let key = "hapticIsland"
    @MainActor static func tap() {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: Auto-collapse after inactivity

/// Closes the open panel after `idleCollapse` seconds without any input (0 keeps it open), unless it is pinned.
@MainActor
final class IdleCollapse {
    static let shared = IdleCollapse()
    nonisolated static let key = "idleCollapse"
    private var timer: Timer?

    nonisolated static func shouldCollapse(expanded: Bool, pinned: Bool, idle: TimeInterval, limit: Int) -> Bool {
        limit > 0 && expanded && !pinned && idle >= Double(limit)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let m = NotchModel.shared
                let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
                if Self.shouldCollapse(expanded: m.expanded, pinned: m.pinnedOpen, idle: idle, limit: UserDefaults.standard.integer(forKey: Self.key)) { m.collapse() }
            }
        }
    }
}

// MARK: Hide the pointer when idle

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
                if !warned { warned = true; NotchModel.shared.show(Activity(symbol: "cursorarrow.slash", title: L("Hiding the pointer is not supported on this Mac"), tint: .orange)) }
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

enum Mirroring {
    static let key = "hideWhileMirroring"
    /// True when any display is in a mirror set (a projector or a TV showing the same picture).
    static var active: Bool {
        NSScreen.screens.contains { s in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
    }
    static var shouldHide: Bool { UserDefaults.standard.bool(forKey: key) && active }
}

// MARK: Swipe the resting notch to change desktop

enum SpaceSwipe {
    static let key = "swipeSpaces"
    /// Sends ⌃← or ⌃→, the Mission Control shortcuts, so macOS moves to the neighbouring Space (needs Accessibility).
    @MainActor static func go(left: Bool) {
        guard AXIsProcessTrusted() else {
            NotchModel.shared.show(Activity(symbol: "hand.raised.fill", title: L("Accessibility needed"), subtitle: L("Allow Pillbox to switch desktops"), tint: .orange,
                                            actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.accessibility) }, duration: 5))
            return
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: left ? 123 : 124, keyDown: down)
            e?.flags = .maskControl; e?.post(tap: .cghidEventTap)
        }
    }
}
