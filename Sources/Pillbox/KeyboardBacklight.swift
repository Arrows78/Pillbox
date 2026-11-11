import AppKit

// MARK: Keyboard backlight (private CoreBrightness client, the one System Settings uses)

/// Steps the keyboard backlight from the command palette. The client class is private: on a Mac without a backlit
/// keyboard it is missing and every call does nothing but say so on the island.
@MainActor
enum KeyboardBacklight {
    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    private typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Put = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private static let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSel = NSSelectorFromString("setBrightness:forKeyboard:")

    static var available: Bool { client?.responds(to: getSel) == true && client?.responds(to: setSel) == true }

    /// The built-in keyboard is 1 on current MacBooks; the system's own list wins when it answers.
    private static var keyboardID: UInt64 {
        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let c = client, c.responds(to: idsSel),
              let ids = c.perform(idsSel)?.takeRetainedValue() as? [NSNumber], let first = ids.first else { return 1 }
        return first.uint64Value
    }

    static var level: Float? {
        guard let c = client, available else { return nil }
        return unsafeBitCast(c.method(for: getSel), to: Get.self)(c, getSel, keyboardID)
    }

    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let c = client, available else { return false }
        let clamped = min(max(value, 0), 1)
        lastApplied = clamped
        return unsafeBitCast(c.method(for: setSel), to: Put.self)(c, setSel, clamped, keyboardID)
    }

    /// The level the app last wrote, so the watcher does not show a change the app already showed.
    nonisolated(unsafe) static var lastApplied: Float?

    /// Whether a change in the level should show the island: it moved, and the app did not make it.
    nonisolated static func shouldShow(previous: Float?, current: Float, appliedByApp: Float?) -> Bool {
        guard let previous, abs(previous - current) > 0.01 else { return false }
        if let appliedByApp, abs(appliedByApp - current) <= 0.01 { return false }
        return true
    }

    /// Moves the level by `delta` (between 0 and 1 in total) and shows the new level on the island.
    static func step(_ delta: Float) {
        guard let now = level else {
            NotchModel.shared.show(Activity(symbol: "light.min", title: localized("Keyboard backlight not available"), duration: 2))
            return
        }
        let v = min(max(now + delta, 0), 1)
        set(v)
        NotchModel.shared.show(Activity(symbol: v > 0 ? "light.max" : "light.min", title: localized("Keyboard backlight"), tint: .white, progress: Double(v), duration: 1.4))
    }
}

/// Watches the keyboard backlight, so a change made with the keyboard keys shows an island, as the volume and
/// brightness do. Changes the app makes itself already show theirs.
@MainActor
final class KeyboardBacklightHUD {
    static let shared = KeyboardBacklightHUD()
    private var timer: Timer?
    private var last: Float?

    func start() {
        last = KeyboardBacklight.level
        timer = PowerGate.timer(every: 0.4) { [weak self] in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        guard let v = KeyboardBacklight.level else { return }
        defer { last = v }
        guard KeyboardBacklight.shouldShow(previous: last, current: v, appliedByApp: KeyboardBacklight.lastApplied) else { return }
        NotchModel.shared.show(Activity(symbol: v > 0 ? "light.max" : "light.min", title: localized("Keyboard backlight"), tint: .white,
                                        progress: Double(v), duration: 1.4, priority: .low))
    }
}
