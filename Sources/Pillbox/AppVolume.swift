import AppKit
import CoreAudio
import AudioToolbox
import os

/// One process the HAL knows about (an app or one of its helpers).
struct AudioProcess: Equatable {
    let object: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let playing: Bool
}

enum AppVolumeMath {
    /// Helpers whose bundle ID does not start with their app's.
    static let aliases = ["com.apple.WebKit.GPU": "com.apple.Safari"]

    /// The app a helper belongs to, by bundle ID prefix ("com.google.Chrome.helper" → "com.google.Chrome").
    static func owner(of bundleID: String, among apps: [String]) -> String? {
        if let a = aliases[bundleID], apps.contains(a) { return a }
        return apps.filter { bundleID == $0 || bundleID.hasPrefix($0 + ".") }.max { $0.count < $1.count }
    }

    /// A tap is only needed while the app is quieter than normal or muted.
    /// Boost goes up to 150 %; a tap is needed whenever the gain is away from 100 %, plus for equalized apps.
    static let maxGain: Float = 1.5
    static func needsTap(gain: Float, muted: Bool, equalized: Bool = false) -> Bool { muted || abs(gain - 1) > 0.005 || equalized }

    /// The tapped channel that feeds an output channel: same index, a mono tap feeds every channel, extra ones stay silent.
    static func source(for out: Int, inputs: Int) -> Int? { inputs == 1 ? 0 : out < inputs ? out : nil }

    static func channelCount(_ list: UnsafeMutableAudioBufferListPointer, from first: Int) -> Int {
        var n = 0
        for i in max(first, 0)..<list.count { n += max(Int(list[i].mNumberChannels), 1) }
        return n
    }

    /// Channel `index` of a buffer list as (samples, offset, stride, frames), so interleaved and planar formats read alike.
    /// No allocation: it runs on the real-time audio thread.
    static func channel(_ list: UnsafeMutableAudioBufferListPointer, from first: Int, _ index: Int) -> (UnsafeMutablePointer<Float>, Int, Int, Int)? {
        var k = index
        for i in max(first, 0)..<list.count {
            let b = list[i], n = max(Int(b.mNumberChannels), 1)
            if k < n {
                guard let p = b.mData?.assumingMemoryBound(to: Float.self) else { return nil }
                return (p, k, n, Int(b.mDataByteSize) / MemoryLayout<Float>.size / n)
            }
            k -= n
        }
        return nil
    }
}

/// Shared by the taps: the gain, equalizer switch and "heard" flag that the audio thread reads while the main thread writes.
/// An unfair lock keeps both sides safe; it is cheap enough for the realtime callback.
final class AppTapState: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<(gain: Float, eqOn: Bool, heard: Bool)>
    init(gain: Float) { lock = OSAllocatedUnfairLock(initialState: (gain: gain, eqOn: false, heard: false)) }
    var gain: Float {
        get { lock.withLock { $0.gain } }
        set { lock.withLock { $0.gain = newValue } }
    }
    var eqOn: Bool {
        get { lock.withLock { $0.eqOn } }
        set { lock.withLock { $0.eqOn = newValue } }
    }
    var heard: Bool { lock.withLock { $0.heard } }
    func markHeard() { lock.withLock { $0.heard = true } }
}

enum AudioProcesses {
    /// Every process with an audio connection, from the HAL.
    static func list() -> [AudioProcess] {
        var a = audioAddress(kAudioHardwarePropertyProcessObjectList), size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var pa = audioAddress(kAudioProcessPropertyPID), pid: pid_t = 0, ps = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &pa, 0, nil, &ps, &pid) == noErr else { return nil }
            var ba = audioAddress(kAudioProcessPropertyBundleID), bid: Unmanaged<CFString>?, bs = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let bundle = AudioObjectGetPropertyData(id, &ba, 0, nil, &bs, &bid) == noErr ? (bid?.takeRetainedValue() as String? ?? "") : ""
            var ra = audioAddress(kAudioProcessPropertyIsRunningOutput), running: UInt32 = 0, rs = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(id, &ra, 0, nil, &rs, &running)
            return AudioProcess(object: id, pid: pid, bundleID: bundle, playing: running != 0)
        }
    }

    static func defaultOutputUID() -> String? {
        guard let dev = defaultDevice(input: false) else { return nil }
        var ua = audioAddress(kAudioDevicePropertyDeviceUID), uid: Unmanaged<CFString>?, us = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &ua, 0, nil, &us, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}

/// Mutes one app, or plays it back quieter: a process tap silences the original and, below 100 %, an aggregate
/// device (the current output plus the tap) plays the tapped audio again at the chosen gain.
@available(macOS 14.4, *)
final class AppTap {
    let processes: [AudioObjectID]
    let muted: Bool
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// Gain, equalizer switch and heard flag, shared with the audio thread.
    private let state: AppTapState
    /// Bass, mid and treble of this app's own equalizer; flat leaves the audio untouched.
    let eq = EQProcessor()
    private var rate: Double = 48_000
    private let queue = DispatchQueue(label: "pillbox.appvolume", qos: .userInteractive)
    /// False while the tap has only delivered silence (no audio capture permission, or nothing played yet).
    var heard: Bool { state.heard }

    init?(processes: [AudioObjectID], gain g: Float, muted: Bool, bands: [Double] = [0, 0, 0]) {
        self.processes = processes; self.muted = muted
        state = AppTapState(gain: g)
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.name = "Pillbox Volume"; desc.isPrivate = true
        desc.muteBehavior = muted ? .muted : .mutedWhenTapped
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { stop(); return nil }
        if muted { return }
        guard let out = AudioProcesses.defaultOutputUID() else { stop(); return nil }
        let agg: [String: Any] = [kAudioAggregateDeviceNameKey: "Pillbox Volume", kAudioAggregateDeviceUIDKey: UUID().uuidString,
                                  kAudioAggregateDeviceMainSubDeviceKey: out, kAudioAggregateDeviceIsPrivateKey: true,
                                  kAudioAggregateDeviceIsStackedKey: false, kAudioAggregateDeviceTapAutoStartKey: true,
                                  kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: out]],
                                  kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggregateID) == noErr else { stop(); return nil }
        rate = SystemEQ.sampleRate(aggregateID)
        setBands(bands)
        let tapBuffers = Self.tapBufferCount(tapID), state = self.state, eq = self.eq
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inData, _, outData, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let outs = UnsafeMutableAudioBufferListPointer(outData)
            // The output device's own inputs (a headset mic) come first, the tap's buffers last.
            let first = ins.count - tapBuffers, inputs = AppVolumeMath.channelCount(ins, from: first)
            let g = state.gain, eqOn = state.eqOn
            var sawSignal = false
            for j in 0..<AppVolumeMath.channelCount(outs, from: 0) {
                guard let d = AppVolumeMath.channel(outs, from: 0, j) else { continue }
                var n = 0
                if let k = AppVolumeMath.source(for: j, inputs: inputs), let s = AppVolumeMath.channel(ins, from: first, k) {
                    n = min(s.3, d.3)
                    for f in 0..<n {
                        let v = s.0[f * s.2 + s.1]
                        if v != 0 { sawSignal = true }
                        d.0[f * d.2 + d.1] = min(max(v * g, -1), 1)
                    }
                }
                for f in n..<d.3 { d.0[f * d.2 + d.1] = 0 }
                if eqOn { eq.process(d.0 + d.1, stride: d.2, frames: d.3, channel: j) }
            }
            if sawSignal { state.markHeard() }
        }
        guard status == noErr, let id = procID, AudioDeviceStart(aggregateID, id) == noErr else { stop(); return nil }
    }

    /// Sets this app's bass, mid and treble in dB (-12...12) and switches its equalizer on or off as they are set.
    func setBands(_ bands: [Double]) {
        guard bands.count == 3 else { return }
        eq.configure(bassDB: bands[0], midDB: bands[1], trebleDB: bands[2], rate: rate)
        state.eqOn = bands.contains { $0 != 0 }
    }

    deinit { stop() }

    func setGain(_ g: Float) { state.gain = g }

    /// Buffers the tap delivers: one interleaved buffer, or one per channel when planar.
    private static func tapBufferCount(_ tap: AudioObjectID) -> Int {
        var fmt = AudioStreamBasicDescription(), size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &fmt) == noErr else { return 1 }
        return fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? max(Int(fmt.mChannelsPerFrame), 1) : 1
    }

    func stop() {
        if let id = procID { AudioDeviceStop(aggregateID, id); AudioDeviceDestroyIOProcID(aggregateID, id); procID = nil }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
    }
}

struct AppAudio: Identifiable, Equatable {
    let id: String   // bundle ID of the app
    let name: String
    let icon: NSImage?
    let processes: [AudioObjectID]
    let playing: Bool
}

/// Per-app volume and mute for the Music tab. Settings last for the session; a tap exists only while an app is
/// below 100 % or muted, and every tap goes away on quit (a private tap also dies with the process).
@MainActor
final class AppVolumeService: ObservableObject {
    static let shared = AppVolumeService()
    @Published var showing = false
    @Published var apps: [AppAudio] = []
    @Published private(set) var gains: [String: Float] = [:]
    @Published private(set) var muted: Set<String> = []
    /// Per-app bass, mid and treble, kept across launches.
    @Published private(set) var eqBands: [String: [Double]] = UserDefaults.standard.dictionary(forKey: AppVolumeService.eqKey) as? [String: [Double]] ?? [:]
    nonisolated static let eqKey = "appEqualizer"
    private var taps: [String: AnyObject] = [:]
    /// Apps whose audio capture was refused; not retried until the app stops or its settings change.
    private var denied: Set<String> = []
    private var eqSave: Timer?
    private var timer: Timer?
    private var listening = false
    /// Set by `--render`, which shows sample rows instead of the real processes.
    var preview = false

    static var supported: Bool { if #available(macOS 14.4, *) { true } else { false } }

    func gain(_ id: String) -> Float { gains[id] ?? 1 }
    func isMuted(_ id: String) -> Bool { muted.contains(id) }

    func show() { showing = true; NotchModel.shared.expand(.music) }

    /// Polls the HAL while the mixer is on screen.
    func watch(_ on: Bool) {
        timer?.invalidate(); timer = nil
        guard on, !preview else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }

    func refresh() {
        guard Self.supported else { return }
        listenForOutputChanges()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        let ids = running.compactMap(\.bundleIdentifier)
        var groups: [String: [AudioProcess]] = [:]
        for p in AudioProcesses.list() where p.pid != getpid() {
            let bid = NSRunningApplication(processIdentifier: p.pid)?.bundleIdentifier ?? p.bundleID
            guard let owner = AppVolumeMath.owner(of: bid, among: ids) else { continue }
            groups[owner, default: []].append(p)
        }
        apps = groups.compactMap { id, procs in
            let playing = procs.contains(where: \.playing)
            guard playing || taps[id] != nil, let app = running.first(where: { $0.bundleIdentifier == id }) else { return nil }
            return AppAudio(id: id, name: app.localizedName ?? id, icon: app.icon, processes: procs.map(\.object).sorted(), playing: playing)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Drop settings of apps that quit; rebuild a tap when the app gained or lost a helper.
        for id in Array(taps.keys) where !groups.keys.contains(id) { forget(id) }
        for a in apps where !denied.contains(a.id) && (taps[a.id] != nil || equalizer(a.id).contains(where: { $0 != 0 })) { apply(a.id) }
    }

    func setGain(_ g: Float, for id: String) {
        gains[id] = min(max(g, 0), AppVolumeMath.maxGain)
        denied.remove(id)
        apply(id)
    }

    func equalizer(_ id: String) -> [Double] { eqBands[id] ?? [0, 0, 0] }

    func setEqualizer(_ bands: [Double], for id: String) {
        eqBands[id] = bands
        denied.remove(id)
        apply(id)
        // Saved once the slider settles: every UserDefaults write re-runs the settings-driven updates in AppDelegate.
        eqSave?.invalidate()
        eqSave = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveEqualizer() }
        }
    }

    private func saveEqualizer() {
        eqSave?.invalidate(); eqSave = nil
        UserDefaults.standard.set(eqBands, forKey: Self.eqKey)
    }

    func toggleMute(_ id: String) {
        if muted.contains(id) { muted.remove(id) } else { muted.insert(id) }
        denied.remove(id)
        apply(id)
    }

    private func forget(_ id: String) { drop(id); gains[id] = nil; muted.remove(id); denied.remove(id) }

    private func drop(_ id: String) {
        guard let t = taps.removeValue(forKey: id) else { return }
        if #available(macOS 14.4, *) { (t as? AppTap)?.stop() }
    }

    private func apply(_ id: String) {
        guard #available(macOS 14.4, *), let app = apps.first(where: { $0.id == id }) else { return }
        let g = gain(id), m = isMuted(id), bands = equalizer(id)
        let equalized = bands.contains { $0 != 0 }
        guard AppVolumeMath.needsTap(gain: g, muted: m, equalized: equalized) else { drop(id); return }
        if let t = taps[id] as? AppTap, t.processes == app.processes, t.muted == m { t.setGain(g); t.setBands(bands); return }
        drop(id)
        guard let t = AppTap(processes: app.processes, gain: g, muted: m, bands: bands) else {
            gains[id] = nil; muted.remove(id)
            NotchModel.shared.show(Activity(symbol: "speaker.slash", title: L("Could not change this app's volume"), tint: .orange, duration: 2))
            return
        }
        taps[id] = t
        if !m { verifyHeard(id, t) }
    }

    /// Without audio capture permission a tap only delivers silence, which would turn a volume change into a mute.
    @available(macOS 14.4, *)
    private func verifyHeard(_ id: String, _ t: AppTap) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak t] in
            MainActor.assumeIsolated {
                guard let self, let t, self.taps[id] === t, !t.heard, self.apps.first(where: { $0.id == id })?.playing == true else { return }
                self.drop(id); self.gains[id] = nil; self.denied.insert(id)
                NotchModel.shared.show(Activity(symbol: "waveform.slash", title: L("Allow audio capture for Pillbox"), subtitle: L("Privacy & Security › Screen & System Audio Recording"), tint: .orange, duration: 3.5))
            }
        }
    }

    /// The playback device is part of each aggregate: follow the default output when it changes.
    private func listenForOutputChanges() {
        guard !listening else { return }
        listening = true
        var a = audioAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                for id in Array(self.taps.keys) where !self.isMuted(id) { self.drop(id); self.apply(id) }
            }
        }
    }

    func stopAll() {
        for id in Array(taps.keys) { drop(id) }
        gains = [:]; muted = []
        if eqSave != nil { saveEqualizer() }
    }
}
