import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

enum OCR {
    static func text(in image: CGImage) -> String {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum ScreenGrab {
    enum Failure: Error { case noDisplay }

    /// Captures a rectangle given in AppKit screen coordinates (needs Screen Recording).
    static func capture(_ rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure.noDisplay }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = sourceRect(for: rect, on: screen.frame)
        cfg.width = max(Int(rect.width * screen.backingScaleFactor), 1); cfg.height = max(Int(rect.height * screen.backingScaleFactor), 1)
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
    }

    /// AppKit rect (bottom-left origin, global) to a display-local rect with a top-left origin.
    nonisolated static func sourceRect(for rect: CGRect, on screen: CGRect) -> CGRect {
        CGRect(x: rect.minX - screen.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: Region picker

private final class PickerWindow: NSWindow { override var canBecomeKey: Bool { true } }

private final class PickerView: NSView {
    var start: NSPoint?, current: NSPoint?
    var onDone: ((NSRect?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private var rect: NSRect? { start.flatMap { s in current.map { NSRect(x: min(s.x, $0.x), y: min(s.y, $0.y), width: abs(s.x - $0.x), height: abs(s.y - $0.y)) } } }
    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); current = start; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        guard let r = rect, r.width > 8, r.height > 8, let w = window else { onDone?(nil); return }
        onDone?(w.convertToScreen(r))
    }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }
    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill()
        guard let r = rect else { return }
        NSColor.clear.setFill(); r.fill(using: .copy)
        NSColor.white.setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 1.5; p.stroke()
    }
}

@MainActor
final class RegionPicker {
    static let shared = RegionPicker()
    private var windows: [NSWindow] = []

    func pick(_ done: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        NotchModel.shared.collapse()
        func finish(_ r: NSRect?) { windows.forEach { $0.orderOut(nil) }; windows = []; done(r) }
        for s in NSScreen.screens {
            let w = PickerWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .clear; w.isOpaque = false; w.level = .screenSaver; w.isReleasedWhenClosed = false
            let v = PickerView(frame: NSRect(origin: .zero, size: s.frame.size)); v.onDone = { finish($0) }
            w.contentView = v; w.makeKeyAndOrderFront(nil); w.makeFirstResponder(v)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: Window watch

/// Watches a part of the screen and tells you when its text changes (a percentage, a status, a price).
@MainActor
final class WindowWatch: ObservableObject {
    static let shared = WindowWatch()
    @Published private(set) var region: CGRect?
    @Published private(set) var lastText = ""
    private var timer: Timer?
    private var busy = false

    var watching: Bool { region != nil }

    nonisolated static func normalize(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    nonisolated static func changed(_ old: String, _ new: String) -> Bool { normalize(old) != normalize(new) }

    func choose() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { PermissionsCenter.shared.openSettings(.screenRecording); return }
        RegionPicker.shared.pick { [weak self] r in
            guard let self, let r else { return }
            self.region = r; self.lastText = ""
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { self.check() } }
            self.check()
            NotchModel.shared.show(Activity(symbol: "eye.fill", title: "Watching this area", tint: .blue))
        }
    }

    func stop() { timer?.invalidate(); region = nil; lastText = "" }

    private func check() {
        guard let r = region, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            guard let img = try? await ScreenGrab.capture(r) else { return }
            let text = await Task.detached { OCR.text(in: img) }.value
            let old = lastText
            lastText = text
            if !old.isEmpty, Self.changed(old, text) {
                NotchModel.shared.show(Activity(symbol: "eye.fill", title: "Watched area changed", subtitle: Self.normalize(text).prefix(80).description, tint: .blue, duration: 6))
            }
        }
    }
}

// MARK: Keychain + Ask about screen

enum Keychain {
    static func get(_ service: String, account: String = "default") -> String? {
        var out: AnyObject?
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, _ service: String, account: String = "default") -> Bool {
        delete(service, account: account)
        guard !value.isEmpty else { return true }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecValueData as String: Data(value.utf8)]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ service: String, account: String = "default") {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

@MainActor
final class AskModel: ObservableObject {
    static let keyService = "dev.labs.pillbox.anthropic"
    @Published var text: String
    @Published var question = ""
    @Published var answer = ""
    @Published var busy = false
    @Published var error: String?
    init(text: String) { self.text = text }

    var hasKey: Bool { Keychain.get(Self.keyService) != nil }

    /// Links and dates found in the text.
    nonisolated static func links(in text: String) -> [URL] {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return d.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    /// Only the recognised text leaves the Mac, never the picture.
    nonisolated static func requestBody(text: String, question: String) -> Data {
        let prompt = "Here is text read from my screen:\n\n\(text.prefix(12_000))\n\nQuestion: \(question)"
        let obj: [String: Any] = ["model": "claude-sonnet-5-5", "max_tokens": 1024, "messages": [["role": "user", "content": prompt]]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    nonisolated static func parseAnswer(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let blocks = root["content"] as? [[String: Any]] else { return nil }
        let t = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        return t.isEmpty ? nil : t
    }

    func ask() {
        guard let key = Keychain.get(Self.keyService), !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true; error = nil; answer = ""
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key"); req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = Self.requestBody(text: text, question: question)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.busy = false
                    if let data, let a = Self.parseAnswer(data) { self.answer = a }
                    else { self.error = err?.localizedDescription ?? L("No answer (check the API key)") }
                }
            }
        }.resume()
    }
}

struct AskView: View {
    @ObservedObject var m: AskModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView { Text(verbatim: m.text.isEmpty ? "—" : m.text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 110).padding(8).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.text, forType: .string) }
                Button("Search") { if let r = WebSearch.resolve(String(m.text.prefix(120))) { NSWorkspace.shared.open(r.url) } }
                Button("Translate") { if let r = WebSearch.resolve("tr " + String(m.text.prefix(500))) { NSWorkspace.shared.open(r.url) } }
                ForEach(Array(AskModel.links(in: m.text).prefix(2)), id: \.self) { u in Button { NSWorkspace.shared.open(u) } label: { Label(u.host ?? "link", systemImage: "link") } }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }.controlSize(.small)
            if m.hasKey {
                HStack {
                    TextField("Ask a question about this text", text: $m.question).textFieldStyle(.roundedBorder).onSubmit { m.ask() }
                    Button("Ask") { m.ask() }.disabled(m.busy)
                }.controlSize(.small)
                if m.busy { ProgressView().controlSize(.small) }
                if !m.answer.isEmpty { ScrollView { Text(verbatim: m.answer).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90) }
                if let e = m.error { Text(verbatim: e).font(.caption).foregroundStyle(.orange) }
            } else {
                Text("Add an Anthropic API key in Settings to ask questions. Only the recognised text is sent.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(width: 520).foregroundStyle(.white).background(.black).environment(\.colorScheme, .dark)
    }
}

@MainActor
enum AskAboutScreen {
    private static var panel: NSPanel?

    static func start() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { PermissionsCenter.shared.openSettings(.screenRecording); return }
        RegionPicker.shared.pick { r in
            guard let r else { return }
            Task {
                guard let img = try? await ScreenGrab.capture(r) else {
                    NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Could not capture the screen", tint: .orange)); return
                }
                let text = await Task.detached { OCR.text(in: img) }.value
                show(text: text, near: r)
            }
        }
    }

    static func show(text: String, near r: CGRect) {
        panel?.orderOut(nil)
        let model = AskModel(text: text)
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating
        let host = NSHostingView(rootView: AskView(m: model) { p.orderOut(nil) }.clipShape(RoundedRectangle(cornerRadius: 16)))
        p.contentView = host
        let size = host.fittingSize
        p.setFrame(NSRect(x: max(r.minX, 20), y: max(r.minY - size.height - 10, 40), width: 520, height: size.height), display: true)
        p.makeKeyAndOrderFront(nil); panel = p
    }
}
