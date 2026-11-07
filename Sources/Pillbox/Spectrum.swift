import AppKit
import CoreAudio
import AudioToolbox

enum Goertzel {
    static let bands: [Double] = [60, 170, 500, 1400, 3500, 8000]

    /// Amplitude of one frequency in a block of samples (a single bin of the DFT, no FFT needed for six bands).
    static func magnitude(_ samples: [Float], sampleRate: Double, frequency: Double) -> Float {
        let n = samples.count
        guard n > 0 else { return 0 }
        let k = (Double(n) * frequency / sampleRate).rounded()
        let coeff = 2 * cos(2 * Double.pi * k / Double(n))
        var s1 = 0.0, s2 = 0.0
        for x in samples { let s0 = Double(x) + coeff * s1 - s2; s2 = s1; s1 = s0 }
        return Float(sqrt(max(s1 * s1 + s2 * s2 - coeff * s1 * s2, 0)) / Double(n) * 2)
    }

    static func levels(_ samples: [Float], sampleRate: Double) -> [Float] {
        bands.map { min(magnitude(samples, sampleRate: sampleRate, frequency: $0) * 4, 1) }
    }
}

/// Levels of the real system audio through a Core Audio process tap (macOS 14.4+, needs audio capture permission).
@MainActor
final class AudioSpectrum: ObservableObject {
    static let shared = AudioSpectrum()
    @Published private(set) var bands: [Float] = Array(repeating: 0, count: Goertzel.bands.count)
    private(set) var running = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "pillbox.spectrum")

    func apply() { UserDefaults.standard.bool(forKey: "liveSpectrum") ? start() : stop() }

    private func start() {
        guard !running else { return }
        guard #available(macOS 14.4, *) else { return }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "Pillbox"; desc.isPrivate = true; desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return }
        var fmt = AudioStreamBasicDescription(); var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fa = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(tapID, &fa, 0, nil, &size, &fmt)
        let rate = fmt.mSampleRate > 0 ? fmt.mSampleRate : 48_000
        let agg: [String: Any] = [kAudioAggregateDeviceNameKey: "Pillbox Tap", kAudioAggregateDeviceUIDKey: UUID().uuidString,
                                  kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
                                  kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
        guard AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggregateID) == noErr else { stop(); return }
        var window = [Float](); window.reserveCapacity(2048)
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            guard let buf = list.first, let p = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
            let channels = max(Int(buf.mNumberChannels), 1), frames = Int(buf.mDataByteSize) / MemoryLayout<Float>.size / channels
            for i in 0..<frames { window.append(p[i * channels]) }
            if window.count >= 1024 {
                let levels = Goertzel.levels(Array(window.suffix(1024)), sampleRate: rate)
                window.removeAll(keepingCapacity: true)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.smooth(levels) } }
            }
        }
        guard status == noErr, let id = procID, AudioDeviceStart(aggregateID, id) == noErr else { stop(); return }
        running = true
    }

    private func smooth(_ new: [Float]) {
        bands = zip(bands, new).map { $1 > $0 ? $1 : $0 * 0.82 + $1 * 0.18 }
    }

    func stop() {
        if let id = procID { AudioDeviceStop(aggregateID, id); AudioDeviceDestroyIOProcID(aggregateID, id); procID = nil }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown, #available(macOS 14.4, *) { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        running = false
        bands = Array(repeating: 0, count: Goertzel.bands.count)
    }
}
