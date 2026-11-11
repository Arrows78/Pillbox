import SwiftUI
import Foundation
import AppKit

/// Shows an island with a stopwatch while `xcodebuild` or `swift build` runs, and its duration when it ends.
@MainActor
final class BuildWatcher: ObservableObject {
    static let shared = BuildWatcher()
    nonisolated static let names: Set<String> = ["xcodebuild", "swift-build"]
    @Published private(set) var since: Date?
    private var timer: Timer?

    nonisolated static func isBuilding(psOutput: String) -> Bool {
        psOutput.split(separator: "\n").contains { names.contains(($0.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent) }
    }

    func start() {
        timer = PowerGate.timer(every: 2) { [weak self] in
            guard UserDefaults.standard.object(forKey: "buildIsland") as? Bool ?? true else { return }
            DispatchQueue.global(qos: .utility).async {
                let out = Self.ps()
                let building = Self.isBuilding(psOutput: out)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.update(building) } }
            }
        }
    }

    private nonisolated static func ps() -> String {
        ProcessRunner.run("/bin/ps", ["-axo", "comm="]).output
    }

    func update(_ building: Bool, now: Date = Date()) {
        switch (since, building) {
        case (nil, true): since = now; NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        case (let s?, false):
            since = nil
            NotificationCenter.default.post(name: .notchStateChanged, object: nil)
            let secs = Int(now.timeIntervalSince(s))
            if secs >= 5 { NotchModel.shared.show(Activity(symbol: "hammer.fill", title: localized("Build finished"),subtitle: localized("%@", TimerService.format(Double(secs))), tint: .green, duration: 4, kind: .build)) }
        default: break
        }
    }
}

// MARK: Bluetooth batteries (AirPods and other accessories)
