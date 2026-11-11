import Foundation
import AppKit
import Lottie
import SwiftUI

/// Two quick presses of the Control key open the notch (works on any Mac, needs Input Monitoring).
struct DoubleTapDetector {
    var window: TimeInterval = 0.35
    private var last: Date?
    mutating func press(at t: Date) -> Bool {
        if let l = last, t.timeIntervalSince(l) < window { last = nil; return true }
        last = t; return false
    }
}

@MainActor
final class DoubleTapKey {
    static let shared = DoubleTapKey()
    private var detector = DoubleTapDetector()
    private var monitor: Any?

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "doubleTapOpen")
        if on, monitor == nil {
            PermissionsCenter.shared.checkInputMonitoring(for: "Double-press Control")
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
                guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { if DoubleTapKey.shared.detector.press(at: Date()) { NotchModel.shared.toggle() } } }
            }
        } else if !on, let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: Snap zones while dragging a window to the notch
