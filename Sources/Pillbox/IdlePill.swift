import Foundation
import AppKit
import SwiftUI

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
