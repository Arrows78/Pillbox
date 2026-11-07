import AppKit
import SwiftUI
import CoreAudio
import CoreMediaIO

private func audioAddress(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

private func defaultDevice(input: Bool) -> AudioDeviceID? {
    var a = audioAddress(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
    var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let r = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
    return r == noErr && id != 0 ? id : nil
}

private func readUInt32(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress) -> UInt32? {
    var a = a; var v: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
}

private func readFloat(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Float32? {
    var a = a; var v: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
}

private func writeValue<T>(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ value: T) -> Bool {
    var a = a; var v = value
    var settable: DarwinBoolean = false
    guard AudioObjectIsPropertySettable(obj, &a, &settable) == noErr, settable.boolValue else { return false }
    return AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
}

// MARK: Privacy indicator (microphone and camera in use)

@MainActor
final class PrivacyService: ObservableObject {
    static let shared = PrivacyService()
    @Published private(set) var micLive = false
    @Published private(set) var cameraLive = false
    var live: Bool { micLive || cameraLive }
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard UserDefaults.standard.object(forKey: "privacyIndicator") as? Bool ?? true else {
            micLive = false; cameraLive = false; return
        }
        let mic = defaultDevice(input: true).flatMap { readUInt32($0, audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)) } == 1
        let cam = Self.cameraRunning()
        if mic != micLive { micLive = mic; if mic { announce("mic.fill", "Microphone in use", .orange) } }
        if cam != cameraLive { cameraLive = cam; if cam { announce("video.fill", "Camera in use", .green) } }
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

@MainActor
final class AudioControl: ObservableObject {
    static let shared = AudioControl()
    @Published private(set) var micMuted = false
    private var savedMicVolume: Float32 = 1
    private var listenerDevice: AudioDeviceID?
    private var lastVolume: Float32 = -1

    /// Mutes the input device itself, so every app (Zoom, Meet, Teams) goes silent.
    func toggleMic() {
        guard let dev = defaultDevice(input: true) else { return }
        let target = !micMuted
        var ok = writeValue(dev, audioAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput), UInt32(target ? 1 : 0))
        if !ok {
            let vol = audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput)
            if target { savedMicVolume = readFloat(dev, vol) ?? 1 }
            ok = writeValue(dev, vol, Float32(target ? 0 : max(savedMicVolume, 0.1)))
        }
        guard ok else {
            NotchModel.shared.show(Activity(symbol: "mic.slash", title: "This microphone can't be muted", tint: .orange)); return
        }
        micMuted = target
        NotchModel.shared.show(Activity(symbol: target ? "mic.slash.fill" : "mic.fill", title: target ? "Microphone muted" : "Microphone on",
                                        tint: target ? .red : .green, duration: 1.8))
    }

    func startVolumeHUD() {
        attachVolumeListener()
        var a = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachVolumeListener() }
        }
    }

    private func attachVolumeListener() {
        guard let dev = defaultDevice(input: false) else { return }
        listenerDevice = dev
        lastVolume = readFloat(dev, audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)) ?? -1
        for sel in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var a = audioAddress(sel, scope: kAudioDevicePropertyScopeOutput)
            AudioObjectAddPropertyListenerBlock(dev, &a, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.volumeChanged() }
            }
        }
    }

    private func volumeChanged() {
        guard UserDefaults.standard.object(forKey: "volumeHUD") as? Bool ?? true, let dev = listenerDevice else { return }
        let v = readFloat(dev, audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)) ?? 0
        let muted = readUInt32(dev, audioAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)) == 1
        guard v != lastVolume || muted else { return }
        lastVolume = v
        let symbol = muted || v == 0 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        NotchModel.shared.show(Activity(symbol: symbol, title: "Volume", tint: .white, progress: muted ? 0 : Double(v), duration: 1.4))
    }
}
