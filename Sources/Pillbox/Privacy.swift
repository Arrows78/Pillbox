import Foundation
import AppKit
import SwiftUI
import CoreAudio
import CoreMediaIO

@MainActor
final class PrivacyService: ObservableObject {
    static let shared = PrivacyService()
    @Published private(set) var micLive = false
    @Published private(set) var cameraLive = false
    var live: Bool { micLive || cameraLive }
    private var timer: Timer?

    func start() {
        timer = PowerGate.timer(every: 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private var cameraWasLive: Bool?   // nil until the first poll, so a camera already on at launch is not announced

    private func poll() {
        let indicator = UserDefaults.standard.object(forKey: "privacyIndicator") as? Bool ?? true, camGuard = Preferences.cameraGuard.value
        let cam = indicator || camGuard ? Self.cameraRunning() : false
        if cam && cameraWasLive == false && camGuard { CameraGuard.cameraStarted() }
        cameraWasLive = cam
        guard indicator else {
            micLive = false; cameraLive = false; return
        }
        let mic = defaultDevice(input: true).flatMap { readUInt32($0, audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)) } == 1
        if mic != micLive { micLive = mic; if mic { announce("mic.fill", localized("Microphone in use"), .orange) } }
        if cam != cameraLive { cameraLive = cam; if cam && !camGuard { announce("video.fill", localized("Camera in use"), .green) } }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }

    private func announce(_ symbol: String, _ title: String, _ tint: Color) {
        NotchModel.shared.show(Activity(symbol: symbol, title: title, tint: tint, duration: 2.5))
    }

    private static func cameraRunning() -> Bool {
        var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                          mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                          mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &a, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var r = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var v: UInt32 = 0; var vs: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &r, 0, nil, UInt32(MemoryLayout<UInt32>.size), &vs, &v) == 0, v != 0 { return true }
        }
        return false
    }
}

// MARK: Mic mute + volume HUD
