import Foundation
import AppKit
import AVFoundation
import SwiftUI

/// Suggests a break after a long stretch of activity; one minute without input counts as a break.
struct BreakLogic {
    private var activeSince: Date?
    mutating func tick(idle: TimeInterval, now: Date, every: TimeInterval) -> Bool {
        if idle >= 60 { activeSince = nil; return false }
        guard let s = activeSince else { activeSince = now; return false }
        if now.timeIntervalSince(s) >= every { activeSince = now; return true }
        return false
    }
}

@MainActor
final class BreakReminder {
    static let shared = BreakReminder()
    private var logic = BreakLogic()
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        let minutes = UserDefaults.standard.integer(forKey: "breakReminder")
        guard minutes > 0 else { logic = BreakLogic(); return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if logic.tick(idle: idle, now: Date(), every: Double(minutes) * 60) {
            NotchModel.shared.show(Activity(symbol: "figure.walk", title: localized("Time for a break"),subtitle: localized("You have been working for %d min", minutes), tint: .green, duration: 8))
        }
    }
}

// MARK: Download progress
