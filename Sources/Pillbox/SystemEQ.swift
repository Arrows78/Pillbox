import CoreAudio
import Foundation

// MARK: Three-band equalizer for the whole system output

/// Biquad coefficients from the RBJ audio EQ cookbook (normalised so a0 is 1).
struct Biquad {
    struct Coefficients { var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0 }

    /// A peaking band at `frequency`, Q 1.
    static func peak(_ frequency: Double, gainDB: Double, rate: Double) -> Coefficients {
        let A = pow(10, gainDB / 40), w = 2 * Double.pi * frequency / rate, alpha = sin(w) / 2, c = cos(w)
        let a0 = 1 + alpha / A
        return Coefficients(b0: (1 + alpha * A) / a0, b1: -2 * c / a0, b2: (1 - alpha * A) / a0, a1: -2 * c / a0, a2: (1 - alpha / A) / a0)
    }

    /// A low shelf (`high` false) or high shelf, slope 1.
    static func shelf(_ frequency: Double, gainDB: Double, rate: Double, high: Bool) -> Coefficients {
        let A = pow(10, gainDB / 40), w = 2 * Double.pi * frequency / rate, c = cos(w)
        let alpha = sin(w) / 2 * 2.0.squareRoot(), sA = 2 * A.squareRoot() * alpha
        if high {
            let a0 = (A + 1) - (A - 1) * c + sA
            return Coefficients(b0: A * ((A + 1) + (A - 1) * c + sA) / a0, b1: -2 * A * ((A - 1) + (A + 1) * c) / a0,
                                b2: A * ((A + 1) + (A - 1) * c - sA) / a0, a1: 2 * ((A - 1) - (A + 1) * c) / a0, a2: ((A + 1) - (A - 1) * c - sA) / a0)
        }
        let a0 = (A + 1) + (A - 1) * c + sA
        return Coefficients(b0: A * ((A + 1) - (A - 1) * c + sA) / a0, b1: 2 * A * ((A - 1) - (A + 1) * c) / a0,
                            b2: A * ((A + 1) - (A - 1) * c - sA) / a0, a1: -2 * ((A - 1) + (A + 1) * c) / a0, a2: ((A + 1) + (A - 1) * c - sA) / a0)
    }

    /// The gain in dB the filter gives at `frequency`.
    static func gainDB(_ k: Coefficients, at frequency: Double, rate: Double) -> Double {
        let w = 2 * Double.pi * frequency / rate
        let num = pow(k.b0 + k.b1 * cos(w) + k.b2 * cos(2 * w), 2) + pow(k.b1 * sin(w) + k.b2 * sin(2 * w), 2)
        let den = pow(1 + k.a1 * cos(w) + k.a2 * cos(2 * w), 2) + pow(k.a1 * sin(w) + k.a2 * sin(2 * w), 2)
        return 10 * log10(num / den)
    }
}

/// Bass, mid and treble bands in series, applied in place to Float32 audio.
final class EQProcessor {
    static let maxChannels = 8
    private let lock = NSLock()
    /// Written by `configure` on the main thread under the lock; the audio thread copies it from there.
    private var pending: [Biquad.Coefficients] = []
    private var pendingGeneration = 0
    /// Used only by the audio thread: the coefficients in effect, and x1, x2, y1, y2 for each channel and band.
    private var bands: [Biquad.Coefficients] = []
    private var appliedGeneration = 0
    private var state = [Double](repeating: 0, count: maxChannels * 3 * 4)

    /// Sets the three gains in dB (-12...12) for a sample rate. The audio thread switches to them on its next buffer.
    func configure(bassDB: Double, midDB: Double, trebleDB: Double, rate: Double) {
        let coefficients = [Biquad.shelf(100, gainDB: bassDB, rate: rate, high: false),
                            Biquad.peak(1_000, gainDB: midDB, rate: rate),
                            Biquad.shelf(8_000, gainDB: trebleDB, rate: rate, high: true)]
        lock.lock(); pending = coefficients; pendingGeneration += 1; lock.unlock()
    }

    /// Filters `frames` samples of one channel, `stride` floats apart, in place.
    func process(_ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int, channel: Int) {
        // The audio thread never waits: if configure holds the lock, the coefficients already in use carry on.
        if lock.`try`() {
            if pendingGeneration != appliedGeneration {
                bands = pending; appliedGeneration = pendingGeneration
                for i in state.indices { state[i] = 0 }
            }
            lock.unlock()
        }
        guard !bands.isEmpty, channel < Self.maxChannels else { return }
        for band in 0..<3 {
            let k = bands[band], s = (channel * 3 + band) * 4
            var x1 = state[s], x2 = state[s + 1], y1 = state[s + 2], y2 = state[s + 3]
            var p = samples
            for _ in 0..<frames {
                let x = Double(p.pointee)
                let y = k.b0 * x + k.b1 * x1 + k.b2 * x2 - k.a1 * y1 - k.a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                p.pointee = Float(y)
                p += stride
            }
            state[s] = x1; state[s + 1] = x2; state[s + 2] = y1; state[s + 3] = y2
        }
    }
}

/// Captures the system output with a Core Audio process tap, equalizes it and plays it on the same output.
/// The tap mutes the original while it runs, so the audio is heard once. Needs the System Audio Recording permission.
@available(macOS 14.2, *)
final class SystemEQ {
    enum Failure: Error { case step(String, OSStatus) }

    let processor = EQProcessor()
    private(set) var running = false
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var rate: Double = 48_000

    /// Called on the main queue when the default output device changes while running.
    var onOutputChange: (() -> Void)?

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutput() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice), id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    private static func string(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        // CoreAudio writes a retained CFString; read it through an Unmanaged reference, as the API documents.
        var addr = address(selector), value: Unmanaged<CFString>? = nil, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// This process's audio object, so the tap can leave out what the equalizer itself plays (or it feeds back on itself).
    private static func ownProcessObject() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject), pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func sampleRate(_ device: AudioObjectID) -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate), rate = 48_000.0, size = UInt32(MemoryLayout<Double>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &rate) == noErr ? rate : 48_000
    }

    func start(bassDB: Double, midDB: Double, trebleDB: Double) throws {
        guard !running else { return }
        do {
            guard let output = Self.defaultOutput(), let outputUID = Self.string(output, kAudioDevicePropertyDeviceUID) else {
                throw Failure.step("default output", OSStatus(kAudioHardwareBadDeviceError))
            }
            let excluded = Self.ownProcessObject().map { [$0] } ?? []
            let tap = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
            tap.name = "Pillbox EQ"
            tap.isPrivate = true
            tap.muteBehavior = .mutedWhenTapped
            var status = AudioHardwareCreateProcessTap(tap, &tapID)
            guard status == noErr else { throw Failure.step("process tap", status) }

            let description: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Pillbox EQ",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceIsStackedKey: 0,
                kAudioAggregateDeviceTapAutoStartKey: 1,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: 1, kAudioSubTapUIDKey: tap.uuid.uuidString]],
            ]
            status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
            guard status == noErr else { throw Failure.step("aggregate device", status) }

            rate = Self.sampleRate(aggregateID)
            processor.configure(bassDB: bassDB, midDB: midDB, trebleDB: trebleDB, rate: rate)
            let p = processor
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
                SystemEQ.render(p, input: input, output: output)
            }
            guard status == noErr else { throw Failure.step("io proc", status) }
            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw Failure.step("start", status) }

            running = true
            listen(true)
        } catch {
            stop()
            throw error
        }
    }

    /// Changes the gains while running, without restarting the tap.
    func setGains(bassDB: Double, midDB: Double, trebleDB: Double) {
        processor.configure(bassDB: bassDB, midDB: midDB, trebleDB: trebleDB, rate: rate)
    }

    func stop() {
        listen(false)
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        running = false
    }

    /// Restarts the tap when the default output changes, so the equalized audio follows the speakers or headphones.
    private func listen(_ on: Bool) {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let system = AudioObjectID(kAudioObjectSystemObject)
        if on, outputListener == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.onOutputChange?() }
            }
            outputListener = block
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
        } else if !on, let block = outputListener {
            AudioObjectRemovePropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            outputListener = nil
        }
    }

    /// The realtime callback: copy the tapped audio to the output, then filter it in place.
    private static func render(_ p: EQProcessor, input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        for i in 0..<outs.count {
            guard let dst = outs[i].mData else { continue }
            memset(dst, 0, Int(outs[i].mDataByteSize))
            if i < ins.count, let src = ins[i].mData {
                memcpy(dst, src, Int(min(ins[i].mDataByteSize, outs[i].mDataByteSize)))
            }
        }
        guard let first = outs.first else { return }
        if outs.count == 1 {
            // Interleaved: channels share one buffer.
            let channels = max(Int(first.mNumberChannels), 1)
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard let base = first.mData?.assumingMemoryBound(to: Float.self) else { return }
            for c in 0..<min(channels, EQProcessor.maxChannels) {
                p.process(base + c, stride: channels, frames: frames, channel: c)
            }
        } else {
            // Planar: one mono buffer per channel.
            for (c, buffer) in outs.enumerated() where c < EQProcessor.maxChannels {
                guard let base = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                p.process(base, stride: 1, frames: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size, channel: c)
            }
        }
    }
}
