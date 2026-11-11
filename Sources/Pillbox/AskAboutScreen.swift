import Foundation
import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

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

    /// The message the API sends with a failed status, with the status itself.
    nonisolated static func apiError(_ data: Data?, status: Int) -> String {
        let root = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let detail = (root?["error"] as? [String: Any])?["message"] as? String { return localized("The API returned status %d: %@", status, detail) }
        return localized("The API returned status %d", status)
    }

    func ask() {
        guard !busy, let key = Keychain.get(Self.keyService), !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
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
                    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if let err { self.error = err.localizedDescription }
                    else if (200..<300).contains(status), let data, let a = Self.parseAnswer(data) { self.answer = a }
                    else if status != 0 { self.error = Self.apiError(data, status: status) }
                    else { self.error = localized("No answer (check the API key)") }
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
                Button("Copy text") { Pasteboard.copy(m.text) }
                Button("Search") { if let r = WebSearch.resolve(String(m.text.prefix(120))) { NSWorkspace.shared.open(r.url) } }
                Button("Translate") { if let r = WebSearch.resolve(TranslateRoute.prefix + " " + String(m.text.prefix(500))) { NSWorkspace.shared.open(r.url) } }
                ForEach(Array(AskModel.links(in: m.text).prefix(2)), id: \.self) { u in Button { NSWorkspace.shared.open(u) } label: { Label(u.host ?? "link", systemImage: "link") } }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close")
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
                    NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not capture the screen"), tint: .orange)); return
                }
                let text = await Task.detached { OCR.recognize(in: img) }.value ?? ""
                show(text: text, near: r)
            }
        }
    }

    static func show(text: String, near r: CGRect) {
        panel?.orderOut(nil)
        let model = AskModel(text: text)
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.styleAsOverlay(level: .floating)
        // Weak: the close button lives in the panel's own hosting view, so a strong capture would keep the panel, model and view alive.
        let host = NSHostingView(rootView: AskView(m: model) { [weak p] in p?.orderOut(nil) }.clipShape(RoundedRectangle(cornerRadius: 16)))
        p.contentView = host
        let size = host.fittingSize
        p.setFrame(NSRect(x: max(r.minX, 20), y: max(r.minY - size.height - 10, 40), width: 520, height: size.height), display: true)
        p.makeKeyAndOrderFront(nil); panel = p
    }
}
