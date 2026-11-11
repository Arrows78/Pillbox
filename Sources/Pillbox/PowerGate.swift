import AppKit

/// Pauses background work while nothing is visible: the Mac sleeps, its screen is locked, or it runs in Low Power Mode.
/// Timers made with `timer(every:)` keep their rhythm but skip their work while paused, so a poll does not read the
/// clipboard, the windows or the stats for a screen nobody sees. Countdowns the user is watching do not use it.
@MainActor
final class PowerGate {
    static let shared = PowerGate()

    var asleep = false
    var locked = false
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var paused: Bool { asleep || locked || lowPower }

    private var observers: [NSObjectProtocol] = []

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerGate.shared.asleep = true }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerGate.shared.asleep = false }
        })
        // The screen lock is announced on the distributed centre, the way the system's own apps hear it.
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerGate.shared.locked = true }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerGate.shared.locked = false }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerGate.shared.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        })
    }

    /// A repeating timer whose `work` runs on each tick unless the gate is paused.
    static func timer(every seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            MainActor.assumeIsolated { if !PowerGate.shared.paused { work() } }
        }
    }
}
