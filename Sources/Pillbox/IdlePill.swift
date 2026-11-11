import Foundation
import AppKit
import SwiftUI

/// The resting pill: what it shows when nothing is live. Off by default; when on, its two wings show the chosen items.
enum IdlePill {
    static let key = "idleClock"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Whether the resting pill has anything to show: it is on and at least one wing has a live item.
    @MainActor static var restingContent: Bool {
        let w = WingLayout.resting(left: Preferences.restingLeft.value, right: Preferences.restingRight.value)
        return enabled && (w.left != nil || w.right != nil)
    }
}

// MARK: Haptics

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
        timer = PowerGate.timer(every: 2) {
            MainActor.assumeIsolated {
                let m = NotchModel.shared
                let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
                if Self.shouldCollapse(expanded: m.expanded, pinned: m.pinnedOpen, idle: idle, limit: UserDefaults.standard.integer(forKey: Self.key)) { m.collapse() }
            }
        }
    }
}

// MARK: Hide the pointer when idle
