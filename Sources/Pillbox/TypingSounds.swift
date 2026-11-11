import AppKit
import AVFoundation
import Carbon.HIToolbox

/// A mechanical-keyboard click on every key press, made from synthesised samples (no recordings shipped).
/// Opt-in, needs Input Monitoring to hear the keys; nothing about which key is pressed is kept.
@MainActor
final class TypingSounds {
    static let shared = TypingSounds()
    nonisolated static let profileKey = "typingSounds", volumeKey = "typingVolume"
    enum Profile: String, CaseIterable, Identifiable {
        case off, soft, clicky, thock
        var id: String { rawValue }
        var title: String {
            switch self { case .off: L("Off"); case .soft: L("Soft"); case .clicky: L("Clicky"); case .thock: L("Thock") }
        }
    }
    static var profile: Profile { Profile(rawValue: UserDefaults.standard.string(forKey: profileKey) ?? "off") ?? .off }
    static var volume: Float { Float(UserDefaults.standard.object(forKey: volumeKey) as? Double ?? 0.5) }

    private var engine: AVAudioEngine?
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var monitors: [Any] = []
    private var loaded: Profile = .off
    private var press: [AVAudioPCMBuffer] = [], release: [AVAudioPCMBuffer] = [], space: AVAudioPCMBuffer?, enter: AVAudioPCMBuffer?
    private var warned = false
    private var audioWarned = false
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    func apply() {
        let p = Self.profile
        if p == .off { teardown(); return }
        if loaded != p { load(p) }
        engine?.mainMixerNode.outputVolume = Self.volume
        guard monitors.isEmpty else { return }
        if !CGPreflightListenEventAccess(), !warned {
            warned = true; _ = CGRequestListenEventAccess()
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: L("Input Monitoring needed"), subtitle: L("Allow Pillbox to hear your keys"), tint: .orange,
                                            actionTitle: L("Settings"), action: { PermissionsCenter.shared.openSettings(.inputMonitoring) }, duration: 6))
        }
        // A monitor that could not be installed is nil and is dropped, so the list only holds live tokens.
        monitors += [
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
                guard !e.isARepeat else { return }
                let code = Int(e.keyCode)
                DispatchQueue.main.async { MainActor.assumeIsolated { TypingSounds.shared.play(down: true, code: code) } }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { e in
                let code = Int(e.keyCode)
                DispatchQueue.main.async { MainActor.assumeIsolated { TypingSounds.shared.play(down: false, code: code) } }
            },
        ].compactMap { $0 }
    }

    private func teardown() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []; engine?.stop(); engine = nil; players = []; loaded = .off
    }

    /// Plays a sample of the chosen profile, for the Settings "Try" button.
    func preview(_ p: Profile) {
        guard p != .off else { return }
        if loaded != p { load(p) }
        engine?.mainMixerNode.outputVolume = Self.volume
        play(down: true, code: kVK_ANSI_A)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { MainActor.assumeIsolated { self.play(down: false, code: kVK_ANSI_A) } }
        if Self.profile == .off { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { if Self.profile == .off { self.teardown() } } } }
    }

    private func load(_ p: Profile) {
        if engine == nil {
            let e = AVAudioEngine()
            players = (0..<6).map { _ in let n = AVAudioPlayerNode(); e.attach(n); e.connect(n, to: e.mainMixerNode, format: Self.format); return n }
            engine = e
        }
        press = (0..<5).map { _ in KeySynth.sample(p, kind: .press) }
        release = (0..<3).map { _ in KeySynth.sample(p, kind: .release) }
        space = KeySynth.sample(p, kind: .space); enter = KeySynth.sample(p, kind: .enter)
        loaded = p
    }

    private func play(down: Bool, code: Int) {
        guard let e = engine, !players.isEmpty else { return }
        if !e.isRunning, (try? e.start()) == nil, !audioWarned {
            // No output device: the keys cannot be heard, so say so once instead of staying silent.
            audioWarned = true
            NotchModel.shared.show(Activity(symbol: "speaker.slash.fill", title: L("Typing sounds cannot play"), subtitle: L("No audio output is available"), tint: .orange, duration: 5))
        }
        let buffer: AVAudioPCMBuffer?
        if !down { buffer = release.randomElement() }
        else if code == kVK_Space { buffer = space }
        else if code == kVK_Return || code == kVK_Delete || code == kVK_ANSI_KeypadEnter { buffer = enter }
        else { buffer = press.randomElement() }
        guard let buffer else { return }
        let node = players[next % players.count]; next += 1
        node.stop(); node.scheduleBuffer(buffer, at: nil); node.play()
    }
}

/// Tiny synthesiser: a noise burst through a resonant band-pass, a low "thump" for the bottom-out and a short click transient.
enum KeySynth {
    enum Kind { case press, release, space, enter }

    /// The numbers that shape one kind of key: band-pass centre (Hz) and resonance, thump and click levels,
    /// length (seconds) and gain.
    struct KeyVoice {
        let freq: Double, q: Double, thump: Double, click: Double, length: Double, gain: Double
    }

    /// One sample, randomised a little so repeated keys do not sound like a machine gun.
    static func sample(_ p: TypingSounds.Profile, kind: Kind) -> AVAudioPCMBuffer {
        let sr = 44100.0
        let v: KeyVoice = {
            switch (p, kind) {
            case (.soft, .press): KeyVoice(freq: 1400, q: 3, thump: 0.35, click: 0.15, length: 0.07, gain: 0.35)
            case (.soft, .release): KeyVoice(freq: 1800, q: 3, thump: 0.05, click: 0.08, length: 0.04, gain: 0.18)
            case (.soft, .space): KeyVoice(freq: 900, q: 2.5, thump: 0.6, click: 0.1, length: 0.09, gain: 0.4)
            case (.soft, .enter): KeyVoice(freq: 1100, q: 2.5, thump: 0.5, click: 0.12, length: 0.08, gain: 0.4)
            case (.clicky, .press): KeyVoice(freq: 3600, q: 9, thump: 0.15, click: 0.8, length: 0.06, gain: 0.45)
            case (.clicky, .release): KeyVoice(freq: 3000, q: 7, thump: 0.0, click: 0.5, length: 0.035, gain: 0.25)
            case (.clicky, .space): KeyVoice(freq: 1600, q: 5, thump: 0.4, click: 0.5, length: 0.08, gain: 0.45)
            case (.clicky, .enter): KeyVoice(freq: 2400, q: 6, thump: 0.3, click: 0.7, length: 0.07, gain: 0.45)
            case (.thock, .press): KeyVoice(freq: 700, q: 2, thump: 0.9, click: 0.2, length: 0.09, gain: 0.5)
            case (.thock, .release): KeyVoice(freq: 1000, q: 2.5, thump: 0.15, click: 0.12, length: 0.045, gain: 0.22)
            case (.thock, .space): KeyVoice(freq: 450, q: 1.8, thump: 1.2, click: 0.15, length: 0.12, gain: 0.55)
            case (.thock, .enter): KeyVoice(freq: 600, q: 2, thump: 1.0, click: 0.2, length: 0.1, gain: 0.5)
            default: KeyVoice(freq: 1500, q: 3, thump: 0.3, click: 0.2, length: 0.07, gain: 0.3)
            }
        }()
        let detune = Double.random(in: 0.92...1.08), vol = Double.random(in: 0.85...1.0)
        let n = Int(sr * v.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        let out = buffer.floatChannelData![0]
        // Band-pass biquad (RBJ) at the body resonance.
        let w0 = 2 * Double.pi * v.freq * detune / sr, alpha = sin(w0) / (2 * v.q)
        let b0 = alpha, b2 = -alpha, a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        let thumpFreq = 110.0 * detune
        for i in 0..<n {
            let t = Double(i) / sr
            let env = exp(-t * (kind == .release ? 90 : 55))
            let x = Double.random(in: -1...1) * env
            let y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x; y2 = y1; y1 = y
            let low = sin(2 * Double.pi * thumpFreq * t) * exp(-t * 70) * v.thump
            let transient = i < 40 ? (1 - Double(i) / 40) * v.click * (i % 2 == 0 ? 1 : -1) : 0
            out[i] = Float(max(-1, min(1, (y * 2.2 + low + transient) * v.gain * vol)))
        }
        return buffer
    }
}
