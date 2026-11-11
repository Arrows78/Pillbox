import AppKit
import Vision

struct ClipItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String?
    var imageFile: String?
    var ocr: String?
    var date = Date()
    var pinned = false
    /// Set when the text looks like a secret. Optional so history saved before this field still loads.
    var secret: Bool?

    var searchable: String { [text, ocr].compactMap { $0 }.joined(separator: " ") }
}

enum SmartKind { case url(URL), color(NSColor, String), email(String), plain }

/// Type filter of the clipboard history.
enum ClipFilter: String, CaseIterable, Identifiable {
    case all, text, links, images, colors
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .links: "link"
        case .images: "photo"
        case .colors: "paintpalette"
        }
    }
    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .links: "Links"
        case .images: "Images"
        case .colors: "Colors"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        guard let t = item.text else { return self == .all || self == .images }
        switch (self, ClipboardService.kind(of: t)) {
        case (.all, _), (.links, .url), (.colors, .color): return true
        case (.text, .plain), (.text, .email): return true
        default: return false
        }
    }
}

@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    static let cap = 60

    @Published var items: [ClipItem] = Store.load("clipboard.json", as: [ClipItem].self) ?? []
    @Published var query = ""
    @Published var filter = ClipFilter.all

    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let imageDir = Store.dir.appendingPathComponent("Clipboard", isDirectory: true)

    func start() {
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        timer = PowerGate.timer(every: 0.5) { [weak self] in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    var filtered: [ClipItem] {
        let sorted = items.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }.filter(filter.matches)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.searchable.localizedCaseInsensitiveContains(query) }
    }

    private func poll() {
        purgeSecrets()
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        // Skip concealed/transient content (password managers).
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        // Copies made while an excluded app is in front are not recorded.
        if ClipboardExclusions.isExcluded(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, in: ClipboardExclusions.ids) { return }

        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let secret = ClipboardSecrets.isSecret(s)
            if let i = items.firstIndex(where: { $0.text == s }) { items[i].date = Date(); items[i].secret = secret }
            else { items.append(ClipItem(text: s, secret: secret)) }
            CopyStackStore.shared.noteCopy(s)
        } else if let img = NSImage(pasteboard: pb) {
            let name = UUID().uuidString + ".png"
            let file = imageDir.appendingPathComponent(name)
            let item = ClipItem(imageFile: name)
            let id = item.id
            items.append(item)
            // Encoding and the write are slow for a screenshot, so they run off the main thread.
            let picture = img
            DispatchQueue.global(qos: .utility).async {
                guard let png = picture.pngData() else { return }
                try? png.write(to: file)
            }
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

    /// Writes the history to disk.
    func save() { Store.save(items, "clipboard.json") }

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
        pb.clearContents()
        if let t = item.text { pb.setString(t, forType: .string) }
        else if let img = image(for: item) { pb.writeObjects([img]) }
        lastChange = pb.changeCount   // our own write is not a new copy
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].date = Date(); save() }
    }

    /// Copies the item then sends ⌘V to the frontmost app (needs Accessibility; falls back to a plain copy).
    func paste(_ item: ClipItem) {
        copy(item)
        sendPasteKey()
    }

    /// Pastes a text item as a plain string: only the string type goes on the pasteboard, so no formatting comes along.
    func pastePlainText(_ item: ClipItem) {
        guard let t = item.text else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(t, forType: .string)
        lastChange = pb.changeCount
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].date = Date(); save() }
        sendPasteKey()
    }

    private func sendPasteKey() {
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

    /// Removes secret items whose time is up. Runs on every poll tick; saves only when something left.
    func purgeSecrets() {
        let ids = Set(ClipboardSecrets.expiredIDs(items, minutes: Preferences.clipboardSecretMinutes.value, now: Date()))
        guard !ids.isEmpty else { return }
        for id in ids { if let f = items.first(where: { $0.id == id })?.imageFile { try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(f)) } }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func togglePin(_ item: ClipItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].pinned.toggle(); save() }
    }

    func remove(_ item: ClipItem) {
        if let f = item.imageFile { try? FileManager.default.removeItem(at: imageDir.appendingPathComponent(f)) }
        items.removeAll { $0.id == item.id }; save()
    }

    func clearUnpinned() {
        for i in items where !i.pinned { remove(i) }
    }

    nonisolated static func kind(of text: String) -> SmartKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: t), let s = u.scheme, ["http", "https"].contains(s), u.host != nil { return .url(u) }
        // A colour needs the leading #: a bare 6-digit code (an SMS code) or a word like "bad" is text.
        if t.range(of: #"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$"#, options: .regularExpression) != nil,
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
