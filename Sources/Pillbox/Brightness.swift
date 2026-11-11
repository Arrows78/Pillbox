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
        return unsafeBitCast(sym, to: GetFn.self)(CGMainDisplayID(), &v) == 0 ? v : nil
    }
}

@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()
    private var timer: Timer?
    private var last: Float?

    func start() {
        last = DisplayBrightness.current()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        guard let v = DisplayBrightness.current() else { return }
        // Tracked even while the HUD is off, so turning it back on does not show the change made in the meantime.
        defer { last = v }
        guard Defaults.bool("brightnessHUD", default: true), let l = last, abs(l - v) > 0.01 else { return }
        NotchModel.shared.show(Activity(symbol: v < 0.5 ? "sun.min.fill" : "sun.max.fill", title: localized("Brightness"), tint: .yellow, progress: Double(v), duration: 1.4, priority: .low))
    }
}

// MARK: Focus mode
