import AppKit
@preconcurrency import AVFoundation
import SwiftUI

// MARK: Eye breaks (20-20-20)

/// Every 20 minutes at the keyboard, a nudge to look at something 20 feet away for 20 seconds, counted down on the island.
@MainActor
final class EyeBreaks {
    static let shared = EyeBreaks()
    nonisolated static let key = "eyeBreaks"
    static let every: TimeInterval = 20 * 60, rest = 20
    private var logic = BreakLogic()
    private var timer: Timer?
    private var countdown: Timer?
    private var taken: [String: Int] = Store.load("eyebreaks.json", as: [String: Int].self) ?? [:]

    var today: Int { taken[TimerService.dayKey(Date())] ?? 0 }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        guard UserDefaults.standard.bool(forKey: Self.key) else { logic = BreakLogic(); return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if logic.tick(idle: idle, now: Date(), every: Self.every) { begin() }
    }

    /// Shows the 20-second countdown; the island updates in place every second.
    func begin() {
        countdown?.invalidate()
        let k = TimerService.dayKey(Date())
        taken[k, default: 0] += 1
        taken = taken.filter { $0.key > TimerService.dayKey(Calendar.current.date(byAdding: .day, value: -7, to: Date())!) }
        Store.save(taken, "eyebreaks.json")
        var left = Self.rest
        var shown: UUID?      // the island this countdown last put up
        var onScreen = false
        func show() {
            let a = Activity(symbol: "eye", title: localized("Rest your eyes"), subtitle: localized("Look far away for %d s · break %d today", left, today),
                             tint: .mint, progress: Double(left) / Double(Self.rest), duration: Double(left) + 1)
            shown = a.id
            NotchModel.shared.show(a)
        }
        show()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                // Tapping the island dismisses it: once it has left the screen, the countdown stops rather than bringing it back.
                let visible = NotchModel.shared.activity?.id == shown
                if onScreen && !visible { t.invalidate(); self?.countdown = nil; return }
                onScreen = visible
                left -= 1
                if left <= 0 { t.invalidate(); self?.countdown = nil; NotchModel.shared.dismissActivity(); NSSound(named: "Tink")?.play(); return }
                show()
            }
        }
    }
}

// MARK: Ambient noise while focusing

/// White, pink or brown noise made on the fly (no audio file), played while a Focus session runs or on demand from the palette.
@MainActor
final class AmbientNoise: ObservableObject {
    static let shared = AmbientNoise()
    nonisolated static let kindKey = "ambientNoise", volumeKey = "ambientVolume"
    enum Kind: String, CaseIterable, Identifiable {
        case off, white, pink, brown
        var id: String { rawValue }
        var title: String {
            switch self { case .off: localized("Off"); case .white: localized("White noise"); case .pink: localized("Pink noise"); case .brown: localized("Brown noise") }
        }
    }
    static var kind: Kind { Kind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "off") ?? .off }
    static var volume: Float { Float(UserDefaults.standard.object(forKey: volumeKey) as? Double ?? 0.3) }

    @Published private(set) var playing = false
    private var engine: AVAudioEngine?
    private var fade: Timer?
    private let state = NoiseState()

    /// Starts with the Focus timer when a kind is chosen.
    func autoStart() { if Self.kind != .off { play(Self.kind) } }
    func autoStop() { stop() }

    func play(_ kind: Kind) {
        guard kind != .off else { stop(); return }
        fade?.invalidate(); fade = nil
        state.kind = kind
        if engine == nil {
            let e = AVAudioEngine()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            let node = AVAudioSourceNode(format: format) { [state] _, _, frames, list in
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                for i in 0..<Int(frames) { out[i] = state.next() }
                return noErr
            }
            e.attach(node); e.connect(node, to: e.mainMixerNode, format: format)
            engine = e
        }
        engine?.mainMixerNode.outputVolume = Self.volume
        if engine?.isRunning != true {
            // Without an output device the engine does not start: say so rather than show "playing" in silence.
            do { try engine?.start() } catch {
                NotchModel.shared.show(Activity(symbol: "speaker.slash.fill", title: localized("Could not play the sound"), subtitle: localized("No audio output is available"), tint: .orange, duration: 4))
                return
            }
        }
        playing = true
    }

    func toggle() { playing ? stop() : play(Self.kind == .off ? .brown : Self.kind) }

    /// Fades out over a second so the end of a session is not a cut.
    func stop() {
        guard playing, let e = engine else { return }
        playing = false
        fade?.invalidate()
        fade = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                e.mainMixerNode.outputVolume = max(0, e.mainMixerNode.outputVolume - Self.volume / 20)
                if e.mainMixerNode.outputVolume <= 0 || self?.playing == true { t.invalidate(); self?.fade = nil; if self?.playing != true { e.pause() } }
            }
        }
    }

    func setVolume(_ v: Float) { engine?.mainMixerNode.outputVolume = v }
}

/// Noise generator shared with the audio thread: white is random, pink filters it (Paul Kellet), brown integrates it.
/// `kind` is written on the main thread and read on the audio thread, so it sits behind a lock that is held only for the copy.
final class NoiseState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedKind: AmbientNoise.Kind = .brown
    var kind: AmbientNoise.Kind {
        get { lock.lock(); defer { lock.unlock() }; return storedKind }
        set { lock.lock(); defer { lock.unlock() }; storedKind = newValue }
    }
    private var rng = SystemRandomNumberGenerator()
    private var pinkBands = [Float](repeating: 0, count: 7)   // the filter's running state
    private var brown: Float = 0

    func next() -> Float {
        let w = Float.random(in: -1...1, using: &rng)
        switch kind {
        case .white, .off: return w * 0.25
        case .pink:
            pinkBands[0] = 0.99886 * pinkBands[0] + w * 0.0555179; pinkBands[1] = 0.99332 * pinkBands[1] + w * 0.0750759; pinkBands[2] = 0.96900 * pinkBands[2] + w * 0.1538520
            pinkBands[3] = 0.86650 * pinkBands[3] + w * 0.3104856; pinkBands[4] = 0.55000 * pinkBands[4] + w * 0.5329522; pinkBands[5] = -0.7616 * pinkBands[5] - w * 0.0168980
            let p = pinkBands[0] + pinkBands[1] + pinkBands[2] + pinkBands[3] + pinkBands[4] + pinkBands[5] + pinkBands[6] + w * 0.5362
            pinkBands[6] = w * 0.115926
            return p * 0.08
        case .brown:
            brown = (brown + 0.02 * w) / 1.02
            return brown * 3.5
        }
    }
}

/// Menu in the Timer tab: pick the sound that plays during Focus sessions.
struct AmbientMenu: View {
    @ObservedObject var noise = AmbientNoise.shared
    @AppStorage(AmbientNoise.kindKey) private var kind = "off"

    var body: some View {
        Menu {
            ForEach(AmbientNoise.Kind.allCases) { k in
                Button { kind = k.rawValue; if noise.playing || TimerService.shared.running { noise.play(k) } } label: {
                    Text(verbatim: (kind == k.rawValue ? "✓ " : "") + k.title)
                }
            }
            Divider()
            Button(LocalizedStringKey(noise.playing ? "Stop the sound" : "Play now")) { noise.toggle() }
        } label: {
            Image(systemName: noise.playing ? "speaker.wave.2.fill" : "speaker.wave.2").foregroundStyle(noise.playing ? Color.orange : .white.opacity(0.6))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().font(.system(size: 13))
        .hoverTip(localized("Ambient sound during focus")).accessibilityLabel("Ambient sound during focus")
    }
}
