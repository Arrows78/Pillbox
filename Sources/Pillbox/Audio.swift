import AppKit
import SwiftUI
import CoreAudio
import CoreMediaIO

/// The CoreAudio property address used across the app (AppVolume reads its process list with it too).
func audioAddress(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

/// The default input or output device, nil when there is none.
func defaultDevice(input: Bool) -> AudioDeviceID? {
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

private func writeValue<T: BitwiseCopyable>(_ obj: AudioObjectID, _ a: AudioObjectPropertyAddress, _ value: T) -> Bool {
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

    private var cameraWasLive: Bool?   // nil until the first poll, so a camera already on at launch is not announced

    private func poll() {
        let indicator = UserDefaults.standard.object(forKey: "privacyIndicator") as? Bool ?? true, camGuard = UserDefaults.standard.bool(forKey: "cameraGuard")
        let cam = indicator || camGuard ? Self.cameraRunning() : false
        if cam && cameraWasLive == false && camGuard { CameraGuard.cameraStarted() }
        cameraWasLive = cam
        guard indicator else {
            micLive = false; cameraLive = false; return
        }
        let mic = defaultDevice(input: true).flatMap { readUInt32($0, audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)) } == 1
        if mic != micLive { micLive = mic; if mic { announce("mic.fill", L("Microphone in use"), .orange) } }
        if cam != cameraLive { cameraLive = cam; if cam && !camGuard { announce("video.fill", L("Camera in use"), .green) } }
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
    /// Listeners on the current output and input device, removed again when the default device changes.
    private typealias DeviceListener = (device: AudioDeviceID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)
    private var outputListeners: [DeviceListener] = []
    private var inputListeners: [DeviceListener] = []

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
            NotchModel.shared.show(Activity(symbol: "mic.slash", title: L("This microphone can't be muted"), tint: .orange)); return
        }
        micMuted = target
        NotchModel.shared.show(Activity(symbol: target ? "mic.slash.fill" : "mic.fill", title: target ? L("Microphone muted") : L("Microphone on"),
                                        tint: target ? .red : .green, duration: 1.8))
    }

    /// The mute state of the current input device, read from the device (it can change outside Pillbox).
    private func readMicMuted() -> Bool {
        guard let dev = defaultDevice(input: true) else { return false }
        var mute = audioAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
        if AudioObjectHasProperty(dev, &mute), let m = readUInt32(dev, mute) { return m == 1 }
        // Devices without a mute switch are muted by setting their volume to zero (see toggleMic).
        return readFloat(dev, audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput)) == 0
    }

    func startVolumeHUD() {
        attachVolumeListener(); attachMicListener()
        var a = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachVolumeListener() }
        }
        var i = audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &i, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachMicListener() }
        }
    }

    /// Adds a property listener on a device; the returned entry lets it be removed later.
    private func listen(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, _ handler: @escaping () -> Void) -> DeviceListener {
        let address = audioAddress(sel, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        var a = address
        AudioObjectAddPropertyListenerBlock(dev, &a, .main, block)
        return (dev, address, block)
    }

    private func unlisten(_ listeners: inout [DeviceListener]) {
        for l in listeners { var a = l.address; AudioObjectRemovePropertyListenerBlock(l.device, &a, .main, l.block) }
        listeners = []
    }

    private func attachVolumeListener() {
        unlisten(&outputListeners)
        guard let dev = defaultDevice(input: false) else { return }
        listenerDevice = dev
        lastVolume = readFloat(dev, audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)) ?? -1
        outputListeners = [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute].map { sel in
            listen(dev, sel, scope: kAudioDevicePropertyScopeOutput) { [weak self] in self?.volumeChanged() }
        }
    }

    private func attachMicListener() {
        unlisten(&inputListeners)
        micMuted = readMicMuted()
        guard let dev = defaultDevice(input: true) else { return }
        inputListeners = [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar].map { sel in
            listen(dev, sel, scope: kAudioDevicePropertyScopeInput) { [weak self] in self?.micMuted = self?.readMicMuted() ?? false }
        }
    }

    private func volumeChanged() {
        guard UserDefaults.standard.object(forKey: "volumeHUD") as? Bool ?? true, let dev = listenerDevice else { return }
        let v = readFloat(dev, audioAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)) ?? 0
        let muted = readUInt32(dev, audioAddress(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)) == 1
        guard v != lastVolume || muted else { return }
        lastVolume = v
        let symbol = muted || v == 0 ? "speaker.slash.fill" : v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        NotchModel.shared.show(Activity(symbol: symbol, title: L("Volume"), tint: .white, progress: muted ? 0 : Double(v), duration: 1.4, priority: .low))
    }
}

// MARK: Output device switcher

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

extension AudioControl {
    static func outputDevices() -> [OutputDevice] {
        var a = audioAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var sa = audioAddress(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var ssize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ssize) == noErr, ssize > 0 else { return nil }
            var na = audioAddress(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nsize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &na, 0, nil, &nsize, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
            return OutputDevice(id: id, name: n as String)
        }
    }

    static func currentOutput() -> AudioDeviceID? { defaultDevice(input: false) }

    func selectOutput(_ d: OutputDevice) {
        let ok = writeValue(AudioObjectID(kAudioObjectSystemObject), audioAddress(kAudioHardwarePropertyDefaultOutputDevice), d.id)
        NotchModel.shared.show(Activity(symbol: ok ? "hifispeaker.fill" : "exclamationmark.triangle", title: ok ? d.name : L("Could not switch the output"),
                                        tint: ok ? .white : .orange, duration: 2))
    }
}
