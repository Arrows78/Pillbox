import Foundation
import AppKit
import SQLite3
import SwiftUI

/// Shows a call as an island with its duration while a known call app is running and the microphone is live.
@MainActor
final class CallMonitor: ObservableObject {
    static let shared = CallMonitor()
    nonisolated static let apps = ["us.zoom.xos": "Zoom", "com.microsoft.teams2": "Teams", "com.microsoft.teams": "Teams", "com.apple.FaceTime": "FaceTime",
                       "net.whatsapp.WhatsApp": "WhatsApp", "com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord", "com.skype.skype": "Skype"]
    @Published private(set) var call: (name: String, since: Date)?
    private var timer: Timer?

    nonisolated static func detect(micLive: Bool, running: [String]) -> String? {
        micLive ? running.compactMap { apps[$0] }.first : nil
    }

    func start() {
        timer = PowerGate.timer(every: 2) { [weak self] in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let name = Defaults.bool("callIsland", default: true) ? Self.detect(micLive: PrivacyService.shared.micLive, running: running) : nil
        switch (call, name) {
        case (nil, let n?):
            call = (n, Date())
            NotchModel.shared.show(Activity(symbol: "phone.fill", title: localized("In a call"), subtitle: n, tint: .green, duration: 3, priority: .high, kind: .call))
        case (let c?, let n?) where c.name != n:
            // A call that moves to another app keeps its start time, under the new name.
            call = (n, c.since)
        case (_?, nil): call = nil
        default: break
        }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }
}
