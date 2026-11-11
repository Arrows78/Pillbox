import Foundation
import AppKit
import SQLite3
import SwiftUI

/// Built-in display brightness through the private DisplayServices framework (absent or failing on other setups: no HUD, no crash).
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func current() -> Float? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var v: Float = 0
        return unsafeBitCast(sym, to: GetFn.self)(builtinDisplay(), &v) == 0 ? v : nil
    }

    /// The laptop's own screen when it is connected: the brightness keys change it even when an external display is the
    /// main one, and the query fails on the external display. Falls back to the main display.
    static func builtinDisplay() -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
}

@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()
    private var timer: Timer?
    private var last: Float?

    func start() {
        last = DisplayBrightness.current()
        timer = PowerGate.timer(every: 0.4) { [weak self] in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        guard let v = DisplayBrightness.current() else { return }
        // Tracked even while the HUD is off, so turning it back on does not show the change made in the meantime.
        defer { last = v }
        guard Defaults.bool("brightnessHUD", default: true), let l = last, abs(l - v) > 0.01 else { return }
        NotchModel.shared.show(Activity(symbol: v < 0.5 ? "sun.min.fill" : "sun.max.fill", title: localized("Brightness"), tint: .yellow, progress: Double(v), duration: 1.4, priority: .low, kind: .brightness))
    }
}

// MARK: Focus mode
