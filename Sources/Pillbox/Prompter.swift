import SwiftUI
import AVFoundation
import Speech

struct PrompterScript: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var title: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? L("Untitled script") : first
    }
}

enum PrompterSpeed: CaseIterable {
    case slow, normal, fast, sprint
    var title: String {
        switch self {
        case .slow: L("Slow")
        case .normal: L("Normal")
        case .fast: L("Fast")
        case .sprint: L("Sprint")
        }
    }
    /// Points per second.
    var points: Double {
        switch self {
        case .slow: 15
        case .normal: 30
        case .fast: 55
        case .sprint: 90
        }
    }
    static func nearest(_ speed: Double) -> PrompterSpeed { allCases.min { abs($0.points - speed) < abs($1.points - speed) }! }
}

/// Word matching for the voice-following mode, kept free of audio so the self-test can run it.
enum PrompterText {
    static func normalize(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// The script's words with the character offset each one starts at.
    static func words(_ script: String) -> [(word: String, start: Int)] {
        var out: [(String, Int)] = []
        var i = script.startIndex
        while i < script.endIndex {
            while i < script.endIndex, script[i].isWhitespace { i = script.index(after: i) }
            let start = i
            while i < script.endIndex, !script[i].isWhitespace { i = script.index(after: i) }
            if start < i {
                let w = normalize(String(script[start..<i]))
                if !w.isEmpty { out.append((w, script.distance(from: script.startIndex, to: start))) }
            }
        }
        return out
    }

    /// Index of the next word to read, given the words just heard. Looks a few words back and a bit ahead of
    /// `from` for the last (up to three) heard words and keeps the closest match; stays put when nothing matches.
    static func advance(_ script: [String], from: Int, heard: [String]) -> Int {
        let tail = Array(heard.map(normalize).filter { !$0.isEmpty }.suffix(3))
        guard !tail.isEmpty, !script.isEmpty else { return from }
        for k in stride(from: tail.count, through: 1, by: -1) {
            let want = Array(tail.suffix(k))
            var best: Int?
            for s in max(0, from - 3)...min(script.count - k, from + 40) where s + k <= script.count {
                if Array(script[s..<s + k]) == want, best.map({ abs(s - from) < abs($0 - from) }) ?? true { best = s }
            }
            if let b = best { return b + k }
        }
        return from
    }
}

/// Listens to the microphone and moves the teleprompter to where you are reading. Recognition runs on the Mac when it can.
@MainActor
final class VoiceFollower {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var words: [String] = []
    private var starts: [Int] = []
    private var total = 1
    private var position = 0
    private var onMove: ((Double) -> Void)?

    static func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speech in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async { MainActor.assumeIsolated { done(speech == .authorized && mic) } }
            }
        }
    }

    /// `onMove` receives the read fraction of the script, 0...1.
    func start(script: String, onMove: @escaping (Double) -> Void) -> Bool {
        stop()
        guard let rec = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), rec.isAvailable else { return false }
        let parsed = PrompterText.words(script)
        words = parsed.map(\.word); starts = parsed.map(\.start); total = max(script.count, 1); position = 0
        self.onMove = onMove
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { request = nil; return false }
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            let heard = result?.bestTranscription.segments.map(\.substring) ?? []
            let finished = error != nil || result?.isFinal == true
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.request === req else { return }
                    if !heard.isEmpty { self.consume(heard) }
                    // The recogniser ends a request after about a minute: start a new one right away.
                    if finished { self.restart(script: self.words.joined(separator: " ")) }
                }
            }
        }
        return true
    }

    private func consume(_ heard: [String]) {
        let next = PrompterText.advance(words, from: position, heard: heard)
        guard next != position else { return }
        position = next
        let i = min(next, starts.count - 1)
        onMove?(starts.isEmpty ? 0 : Double(starts[i]) / Double(total))
    }

    private func restart(script: String) {
        guard let onMove else { return }
        let keep = position
        _ = start(script: script, onMove: onMove)
        position = keep
    }

    func stop() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }
}

@MainActor
final class PrompterStore: ObservableObject {
    static let shared = PrompterStore()
    @Published var scripts: [PrompterScript] = Store.load("prompter.json", as: [PrompterScript].self) ?? []
    @Published var selected: UUID?

    init() {
        if scripts.isEmpty, let old = UserDefaults.standard.string(forKey: "teleScript"), !old.isEmpty { scripts = [PrompterScript(text: old)] }
        selected = scripts.first?.id
    }

    var current: PrompterScript? { scripts.first { $0.id == selected } }

    func add() { let s = PrompterScript(); scripts.insert(s, at: 0); selected = s.id; save() }
    func remove(_ s: PrompterScript) {
        scripts.removeAll { $0.id == s.id }
        if selected == s.id { selected = scripts.first?.id }
        save()
    }
    func setText(_ text: String) {
        guard let i = scripts.firstIndex(where: { $0.id == selected }) else { return }
        scripts[i].text = text; save()
    }
    func save() { Store.save(scripts, "prompter.json") }
}

struct PrompterTab: View {
    @ObservedObject var store = PrompterStore.shared
    @ObservedObject var tele = Teleprompter.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Scripts", systemImage: "books.vertical.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Button { store.add() } label: { Image(systemName: "plus") }.buttonStyle(.plain).accessibilityLabel("New script")
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.scripts) { s in
                            Button { store.selected = s.id } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill").font(.system(size: 10))
                                    Text(verbatim: s.title).lineLimit(1).font(.system(size: 12, weight: .medium))
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(store.selected == s.id ? Color.white.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete", role: .destructive) { store.remove(s) } }
                        }
                    }
                }
            }
            .frame(width: 150)

            VStack(spacing: 8) {
                if store.current != nil {
                    TextEditor(text: Binding(get: { store.current?.text ?? "" }, set: { store.setText($0) }))
                        .font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(6).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3))
                        Text("No script yet").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        ForEach(PrompterSpeed.allCases, id: \.self) { sp in
                            let on = PrompterSpeed.nearest(tele.speed) == sp
                            Button { tele.speed = sp.points } label: {
                                Text(verbatim: sp.title).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 5)
                                    .background(on ? Color.white.opacity(0.2) : .clear, in: Capsule())
                                    .foregroundStyle(on ? .white : .white.opacity(0.5))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(2).background(Color.white.opacity(0.08), in: Capsule())
                    Button { tele.voice.toggle() } label: {
                        Image(systemName: tele.voice ? "mic.fill" : "mic.slash.fill").frame(width: 30, height: 26)
                            .background(tele.voice ? Color.pink.opacity(0.3) : Color.white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain).help("Follow my voice").accessibilityLabel("Follow my voice")
                    Button {
                        guard let s = store.current else { return }
                        tele.begin(script: s.text)
                    } label: { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(PillButtonStyle(tint: .pink)).disabled(store.current?.text.isEmpty ?? true)
                }
            }
        }
    }
}
