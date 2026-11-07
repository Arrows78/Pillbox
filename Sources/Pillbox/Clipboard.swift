import AppKit
import Vision

struct ClipItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String?
    var imageFile: String?
    var ocr: String?
    var date = Date()
    var pinned = false

    var searchable: String { [text, ocr].compactMap { $0 }.joined(separator: " ") }
}

enum SmartKind { case url(URL), color(NSColor, String), email(String), plain }

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    static let cap = 60

    @Published var items: [ClipItem] = Store.load("clipboard.json", as: [ClipItem].self) ?? []
    @Published var query = ""

    private var lastChange = NSPasteboard.general.changeCount
    private var ignoreNext = false
    private var timer: Timer?
    private let imageDir = Store.dir.appendingPathComponent("Clipboard", isDirectory: true)

    func start() {
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    var filtered: [ClipItem] {
        let sorted = items.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.searchable.localizedCaseInsensitiveContains(query) }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        // Skip concealed/transient content (password managers).
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }

        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let i = items.firstIndex(where: { $0.text == s }) { items[i].date = Date() }
            else { items.append(ClipItem(text: s)) }
        } else if let img = NSImage(pasteboard: pb), let png = img.pngData() {
            let name = UUID().uuidString + ".png"
            try? png.write(to: imageDir.appendingPathComponent(name))
            var item = ClipItem(imageFile: name)
            let id = item.id
            item.ocr = nil
            items.append(item)
            recognize(img) { [weak self] text in
                guard let i = self?.items.firstIndex(where: { $0.id == id }) else { return }
                self?.items[i].ocr = text; self?.save()
            }
        } else { return }
        trim(); save()
    }

    func trim() {
        let unpinned = items.filter { !$0.pinned }.sorted { $0.date > $1.date }
        for old in unpinned.dropFirst(Self.cap) {
            if let f = old.imageFile { try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(f)) }
            items.removeAll { $0.id == old.id }
        }
    }

    private func save() { Store.save(items, "clipboard.json") }

    private func recognize(_ image: NSImage, done: @escaping @MainActor (String) -> Void) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        DispatchQueue.global(qos: .utility).async {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            let text = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            DispatchQueue.main.async { MainActor.assumeIsolated { done(text) } }
        }
    }

    func image(for item: ClipItem) -> NSImage? {
        item.imageFile.flatMap { NSImage(contentsOf: imageDir.appendingPathComponent($0)) }
    }

    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        ignoreNext = true
        pb.clearContents()
        if let t = item.text { pb.setString(t, forType: .string) }
        else if let img = image(for: item) { pb.writeObjects([img]) }
        lastChange = pb.changeCount
        if let i = items.firstIndex(of: item) { items[i].date = Date(); save() }
    }

    /// Copies the item then sends ⌘V to the frontmost app (needs Accessibility; falls back to a plain copy).
    func paste(_ item: ClipItem) {
        copy(item)
        NotchModel.shared.collapse()
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down)
                e?.flags = .maskCommand; e?.post(tap: .cghidEventTap)
            }
        }
    }

    func togglePin(_ item: ClipItem) {
        if let i = items.firstIndex(of: item) { items[i].pinned.toggle(); save() }
    }

    func remove(_ item: ClipItem) {
        if let f = item.imageFile { try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(f)) }
        items.removeAll { $0.id == item.id }; save()
    }

    func clearUnpinned() {
        for i in items where !i.pinned { remove(i) }
    }

    static func kind(of text: String) -> SmartKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: t), let s = u.scheme, ["http", "https"].contains(s), u.host != nil { return .url(u) }
        if t.range(of: #"^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$"#, options: .regularExpression) != nil,
           let c = NSColor(hex: t) { return .color(c, t) }
        if t.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil { return .email(t) }
        return .plain
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let t = tiffRepresentation, let r = NSBitmapImageRep(data: t) else { return nil }
        return r.representation(using: .png, properties: [:])
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                  blue: CGFloat(v & 255) / 255, alpha: 1)
    }
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
