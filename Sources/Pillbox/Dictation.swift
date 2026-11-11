import AppKit
import SwiftUI
import AVFoundation
import Speech
import Carbon.HIToolbox

/// Microphone to text, shared by the teleprompter's voice following and dictation. Recognition runs on the Mac
/// when it can. The recogniser ends a request after about a minute: a new one starts right away.
@MainActor
final class SpeechListener {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var began = Date.distantPast
    private var ending = false
    /// Words heard in the current request, its formatted text, and whether the request is over.
    private var onResult: (([String], String, Bool) -> Void)?
    private var onLevel: ((Float) -> Void)?
    /// Called when listening ends on its own (a request that failed at once, or no restart possible).
    private var onStopped: (() -> Void)?

    static func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speech in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { MainActor.assumeIsolated { done(speech == .authorized && mic) } }
            }
        }
    }

    /// Root-mean-square level of a buffer, mapped to 0...1 for a meter.
    nonisolated static func level(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        return min(max((20 * log10(rms) + 50) / 50, 0), 1)   // -50 dB ... 0 dB
    }

    func start(onLevel: ((Float) -> Void)? = nil, onStopped: (() -> Void)? = nil, onResult: @escaping ([String], String, Bool) -> Void) -> Bool {
        stop()
        self.onResult = onResult; self.onLevel = onLevel; self.onStopped = onStopped
        return begin()
    }

    private func begin() -> Bool {
        guard let rec = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), rec.isAvailable else { return false }
        // A restarted request must not leave its entry in `active` behind.
        if let old = request { Self.active[ObjectIdentifier(old)] = nil }
        ending = false; began = Date()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        // With no input device the format has a 0 Hz rate, and a tap on it raises an Objective-C exception.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { request = nil; return false }
        input.removeTap(onBus: 0)
        let metered = onLevel != nil
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buf, _ in
            req.append(buf)
            guard metered, let ch = buf.floatChannelData else { return }
            let v = SpeechListener.level(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
            DispatchQueue.main.async { MainActor.assumeIsolated { SpeechListener.deliverLevel(v, for: req) } }
        }
        engine.prepare()
        do { try engine.start() } catch { request = nil; input.removeTap(onBus: 0); return false }
        Self.active[ObjectIdentifier(req)] = self
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            let words = result?.bestTranscription.segments.map(\.substring) ?? []
            let text = result?.bestTranscription.formattedString ?? ""
            let finished = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.request === req else { return }
                    self.onResult?(words, text, finished)
                    guard finished else { return }
                    // A request that fails at once (no recogniser, no input) is not restarted in a loop.
                    if self.ending { self.stop() }
                    else if Date().timeIntervalSince(self.began) < 1 { self.stop(); self.onStopped?() }
                    else if !self.begin() { self.onStopped?() }
                }
            }
        }
        return true
    }

    private static var active: [ObjectIdentifier: SpeechListener] = [:]
    private static func deliverLevel(_ v: Float, for req: SFSpeechAudioBufferRecognitionRequest) {
        guard let l = active[ObjectIdentifier(req)], l.request === req else { return }
        l.onLevel?(v)
    }

    /// Stops listening but lets the recogniser deliver its final text for what it already heard.
    func finish() {
        ending = true
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    func stop() {
        if let r = request { Self.active[ObjectIdentifier(r)] = nil }
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }
}

/// Text kept across the recogniser's one-minute requests: each finished request is committed, the current one is partial.
struct DictationText: Equatable {
    var committed = ""
    var partial = ""

    mutating func update(_ text: String, finished: Bool) {
        if !text.isEmpty { partial = text }   // a request that ends in an error reports no text: keep what it heard
        if finished { commit() }
    }

    mutating func commit() {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty { committed += (committed.isEmpty ? "" : " ") + p }
        partial = ""
    }

    var full: String {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        return committed + (committed.isEmpty || p.isEmpty ? "" : " ") + p
    }
}

/// Live microphone level, kept apart so only the meter redraws while you speak.
@MainActor
final class DictationMeter: ObservableObject {
    @Published var level: Float = 0
}

/// Speech to text into the front app. The shortcut (or the palette) starts it; the shortcut again or Escape
/// pastes the text where you are typing and copies it; Cancel throws it away.
@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()
    @Published private(set) var active = false
    @Published var text = DictationText()
    let meter = DictationMeter()
    private let listener = SpeechListener()
    private var escape: HotKey?
    private var deliverTask: Task<Void, Never>?
    private var finishing = false

    func toggle() { active ? finish() : start() }

    /// For `--render` only: shows the island without listening.
    func forceActive(_ on: Bool) { active = on }

    func start() {
        guard !active else { return }
        SpeechListener.requestAccess { [weak self] ok in
            guard let self else { return }
            guard ok else {
                NotchModel.shared.show(Activity(symbol: "mic.slash.fill", title: localized("Microphone needed"),
                                                subtitle: localized("Also allow speech recognition"), tint: .orange, actionTitle: "Settings", action: {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
                }, duration: 6))
                return
            }
            self.begin()
        }
    }

    private func begin() {
        guard !active else { return }
        text = DictationText(); finishing = false
        // Listening that ends on its own delivers what was heard, so the island does not stay on "Listening…".
        let ok = listener.start(onLevel: { [weak self] v in self?.meter.level = v }, onStopped: { [weak self] in self?.finish() }) { [weak self] _, t, finished in
            guard let self, self.active else { return }
            self.text.update(t, finished: finished)
            if finished, self.finishing { self.deliver() }
        }
        guard ok else {
            NotchModel.shared.show(Activity(symbol: "mic.slash.fill", title: localized("Speech recognition is not available"), tint: .orange))
            return
        }
        NotchModel.shared.collapse()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { active = true }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        escape = HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0, id: Self.escapeID) { DictationService.shared.finish() }
    }

    static let escapeID: UInt32 = 900

    /// Ends listening; the text goes out once the recogniser has finalised it (or after a second at most).
    func finish() {
        guard active, !finishing else { return }
        finishing = true
        listener.finish()
        deliverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.deliver()
        }
    }

    func cancel() {
        guard active else { return }
        listener.stop()
        end()
    }

    private func deliver() {
        guard active else { return }
        listener.stop()
        let out = text.full
        end()
        guard !out.isEmpty else {
            NotchModel.shared.show(Activity(symbol: "mic.fill", title: localized("Nothing was heard"), tint: .orange)); return
        }
        ClipboardService.shared.paste(ClipItem(text: out))
        if !AXIsProcessTrusted() {
            NotchModel.shared.show(Activity(symbol: "doc.on.clipboard.fill", title: localized("Dictation copied"), subtitle: localized("Allow Accessibility to paste it for you"), tint: .green))
        }
    }

    private func end() {
        deliverTask?.cancel(); deliverTask = nil
        escape?.unregister(); escape = nil
        finishing = false; meter.level = 0
        withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) { active = false }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }
}

struct DictationLevelBars: View {
    @ObservedObject var meter: DictationMeter
    private static let weights: [Float] = [0.55, 0.85, 1, 0.75, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<Self.weights.count, id: \.self) { i in
                Capsule().fill(.red).frame(width: 3, height: 4 + 14 * CGFloat(meter.level * Self.weights[i]))
            }
        }
        .frame(width: 23, height: 18)
        .animation(.easeOut(duration: 0.1), value: meter.level)
        .accessibilityHidden(true)
    }
}

/// The island while dictating: mic, live level, the latest words, Cancel and Done.
struct DictationView: View {
    @ObservedObject var dictation = DictationService.shared
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.red)
            DictationLevelBars(meter: dictation.meter)
            let t = dictation.text.full
            Group {
                if t.isEmpty { Text("Listening…").foregroundStyle(.secondary) }
                else { Text(verbatim: t).truncationMode(.head) }
            }
            .font(Design.bodyMedium).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dictation.cancel() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.white.opacity(0.5)) }
                .buttonStyle(.plain).accessibilityLabel("Cancel")
            Button { dictation.finish() } label: { Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(.green) }
                .buttonStyle(.plain).accessibilityLabel("Done")
        }
        .padding(.horizontal, 18)
        .padding(.top, model.geometry.height)
        .padding(.bottom, 4)
        .foregroundStyle(.white)
    }
}
