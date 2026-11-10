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
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    func apply() {
        let p = Self.profile
        if p == .off { teardown(); return }
        if loaded != p { load(p) }
        engine?.mainMixerNode.outputVolume = Self.volume
        guard monitors.isEmpty else { return }
        if !CGPreflightListenEventAccess(), !warned {
            warned = true; _ = CGRequestListenEventAccess()
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: "Input Monitoring needed", subtitle: "Allow Pillbox to hear your keys", tint: .orange,
                                            actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.inputMonitoring) }, duration: 6))
        }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            guard !e.isARepeat else { return }
            let code = Int(e.keyCode)
            DispatchQueue.main.async { MainActor.assumeIsolated { TypingSounds.shared.play(down: true, code: code) } }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { e in
            let code = Int(e.keyCode)
            DispatchQueue.main.async { MainActor.assumeIsolated { TypingSounds.shared.play(down: false, code: code) } }
        } as Any)
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
        if !e.isRunning { try? e.start() }
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

    /// One sample, randomised a little so repeated keys do not sound like a machine gun.
    static func sample(_ p: TypingSounds.Profile, kind: Kind) -> AVAudioPCMBuffer {
        let sr = 44100.0
        let (freq, q, thump, click, length, gain): (Double, Double, Double, Double, Double, Double) = {
            switch (p, kind) {
            case (.soft, .press): (1400, 3, 0.35, 0.15, 0.07, 0.35)
            case (.soft, .release): (1800, 3, 0.05, 0.08, 0.04, 0.18)
            case (.soft, .space): (900, 2.5, 0.6, 0.1, 0.09, 0.4)
            case (.soft, .enter): (1100, 2.5, 0.5, 0.12, 0.08, 0.4)
            case (.clicky, .press): (3600, 9, 0.15, 0.8, 0.06, 0.45)
            case (.clicky, .release): (3000, 7, 0.0, 0.5, 0.035, 0.25)
            case (.clicky, .space): (1600, 5, 0.4, 0.5, 0.08, 0.45)
            case (.clicky, .enter): (2400, 6, 0.3, 0.7, 0.07, 0.45)
            case (.thock, .press): (700, 2, 0.9, 0.2, 0.09, 0.5)
            case (.thock, .release): (1000, 2.5, 0.15, 0.12, 0.045, 0.22)
            case (.thock, .space): (450, 1.8, 1.2, 0.15, 0.12, 0.55)
            case (.thock, .enter): (600, 2, 1.0, 0.2, 0.1, 0.5)
            default: (1500, 3, 0.3, 0.2, 0.07, 0.3)
            }
        }()
        let detune = Double.random(in: 0.92...1.08), vol = Double.random(in: 0.85...1.0)
        let n = Int(sr * length)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        let out = buffer.floatChannelData![0]
        // Band-pass biquad (RBJ) at the body resonance.
        let w0 = 2 * Double.pi * freq * detune / sr, alpha = sin(w0) / (2 * q)
        let b0 = alpha, b2 = -alpha, a0 = 1 + alpha, a1 = -2 * cos(w0), a2 = 1 - alpha
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        let thumpFreq = 110.0 * detune
        for i in 0..<n {
            let t = Double(i) / sr
            let env = exp(-t * (kind == .release ? 90 : 55))
            let x = Double.random(in: -1...1) * env
            let y = (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = x; y2 = y1; y1 = y
            let low = sin(2 * Double.pi * thumpFreq * t) * exp(-t * 70) * thump
            let transient = i < 40 ? (1 - Double(i) / 40) * click * (i % 2 == 0 ? 1 : -1) : 0
            out[i] = Float(max(-1, min(1, (y * 2.2 + low + transient) * gain * vol)))
        }
        return buffer
    }
}
