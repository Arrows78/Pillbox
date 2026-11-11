import AppKit

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    /// When the file was staged. Files written before this existed count as staged now.
    var added = Date()
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(path: String) { self.path = path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try c.decode(String.self, forKey: .path)
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date()
    }
}

@MainActor
final class ShelfService: ObservableObject {
    static let shared = ShelfService()

    @Published var items: [ShelfItem] = (Store.load("shelf.json", as: [ShelfItem].self) ?? []).filter(\.exists)
    @Published var selection: Set<UUID> = []

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(where: { $0.path == u.path }) { items.append(ShelfItem(path: u.path)) }
        save()
    }

    /// Drops the entries whose file was moved or deleted since they were added. Runs when the tab opens, not only at launch.
    func purgeMissing(now: Date = Date()) {
        let before = items.count
        items.removeAll { !$0.exists }
        // Entries older than the days chosen are dropped from the shelf; the files themselves stay where they are.
        if let cutoff = Self.cutoff(keepDays: Preferences.shelfKeepDays.value, now: now) { items.removeAll { $0.added < cutoff } }
        guard items.count != before else { return }
        selection = selection.filter { id in items.contains { $0.id == id } }
        save()
    }

    /// The date before which a shelf entry is too old, or nil when entries are kept for good (0 days).
    nonisolated static func cutoff(keepDays: Int, now: Date) -> Date? {
        keepDays > 0 ? now.addingTimeInterval(-TimeInterval(keepDays) * 86400) : nil
    }

    func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) }; selection.subtract(ids); save() }
    func clear() { items.removeAll(); selection.removeAll(); save() }
    private func save() { Store.save(items, "shelf.json") }

    var selected: [ShelfItem] { items.filter { selection.contains($0.id) } }

    func airDrop(_ list: [ShelfItem]) {
        let urls = list.map(\.url)
        guard !urls.isEmpty else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Select items first"), tint: .orange))
            return
        }
        guard let svc = NSSharingService(named: .sendViaAirDrop), svc.canPerform(withItems: urls) else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("AirDrop unavailable"), tint: .orange))
            return
        }
        svc.perform(withItems: urls)
    }

    func reveal(_ list: [ShelfItem]) { NSWorkspace.shared.activateFileViewerSelecting(list.map(\.url)) }

    /// Picks files with an open panel and adds them, for when there is nothing at hand to drag.
    func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = true; panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func copyPaths(_ list: [ShelfItem]) {
        Pasteboard.copy(list.map(\.path).joined(separator: "\n"))
    }

    /// Puts the files themselves on the pasteboard, so they paste into Finder and other apps as files.
    func copyFiles(_ list: [ShelfItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(list.map { $0.url as NSURL })
    }

    /// The system share menu for the files, shown under the key window.
    func share(_ list: [ShelfItem]) {
        let urls = list.map(\.url)
        guard !urls.isEmpty, let view = NSApp.keyWindow?.contentView else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Select items first"), tint: .orange))
            return
        }
        NSSharingServicePicker(items: urls).show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// "3 items · 2 selected", the shelf's header line.
    nonisolated static func summary(count: Int, selected: Int) -> String {
        let n = count == 1 ? localized("1 item") : localized("%lld items", count)
        return selected > 0 ? n + " · " + localized("%lld selected", selected) : n
    }

    /// A sibling URL that does not exist yet ("name", "name 2", "name 3"…), so nothing is ever overwritten.
    /// `avoiding` holds paths already planned by the same batch: their programs have not written them yet.
    /// A folder keeps its dots as part of its name ("v1.2" becomes "v1.2 2", not "v1 2.2").
    nonisolated static func uniqueURL(_ url: URL, folder: Bool = false, avoiding taken: Set<String> = []) -> URL {
        let fm = FileManager.default
        func isFree(_ u: URL) -> Bool { !fm.fileExists(atPath: u.path) && !taken.contains(u.path) }
        if isFree(url) { return url }
        let base = folder ? url.path : url.deletingPathExtension().path, ext = folder ? "" : url.pathExtension
        var n = 2
        while true {
            let candidate = URL(fileURLWithPath: base + " \(n)")
            let named = ext.isEmpty ? candidate : candidate.appendingPathExtension(ext)
            if isFree(named) { return named }
            n += 1
        }
    }

    /// Compresses files into a zip (or expands archives into a new folder) with the system `ditto`.
    func zipOrUnzip(_ list: [ShelfItem]) {
        var planned = Set<String>()   // every output of this batch, so two inputs cannot share one
        for item in list {
            let u = item.url
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            let out: URL
            if u.pathExtension.lowercased() == "zip" {
                out = Self.uniqueURL(u.deletingPathExtension(), folder: true, avoiding: planned)
                p.arguments = ["-x", "-k", u.path, out.path]
            } else {
                out = Self.uniqueURL(u.appendingPathExtension("zip"), avoiding: planned)
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
                // --keepParent embeds the parent folder name: wanted for a folder, wrong for a single file.
                p.arguments = ["-c", "-k", "--sequesterRsrc"] + (isDir.boolValue ? ["--keepParent"] : []) + [u.path, out.path]
            }
            p.terminationHandler = { proc in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if proc.terminationStatus == 0 {
                            self.add([out])
                            NotchModel.shared.show(Activity(symbol: "archivebox.fill", title: out.lastPathComponent, tint: .green))
                        } else {
                            NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: localized("Archive failed"), tint: .red))
                        }
                    }
                }
            }
            planned.insert(out.path)
            do { try p.run() } catch { NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: localized("Archive failed"), tint: .red)) }
        }
    }
}

/// Detects a left-right shake: several direction reversals, each after enough travel, within a short window.
struct ShakeDetector {
    var minTravel: CGFloat = 50
    var window: TimeInterval = 0.9
    var reversalsNeeded = 3
    private var lastX: CGFloat?
    private var direction = 0
    private var travel: CGFloat = 0
    private var reversals: [Date] = []

    mutating func reset() { lastX = nil; direction = 0; travel = 0; reversals = [] }

    mutating func add(_ p: CGPoint, at t: Date) -> Bool {
        guard let lx = lastX else { lastX = p.x; return false }
        let dx = p.x - lx
        if abs(dx) < 2 { return false }
        lastX = p.x
        let d = dx > 0 ? 1 : -1
        if d == direction { travel += abs(dx) }
        else {
            if direction != 0, travel >= minTravel { reversals.append(t) }
            direction = d; travel = abs(dx)
        }
        reversals.removeAll { t.timeIntervalSince($0) > window }
        if reversals.count >= reversalsNeeded { reversals = []; return true }
        return false
    }
}

// MARK: Break reminders

extension ShelfService {
    func convert(_ list: [ShelfItem], to target: ConvertTarget) {
        for item in list {
            Task { @MainActor in
                do {
                    let out = try await Converter.convert(item.url, to: target)
                    add([out])
                    NotchModel.shared.show(Activity(symbol: "arrow.triangle.2.circlepath", title: localized("Converted"), subtitle: out.lastPathComponent, tint: .green))
                } catch {
                    NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: localized("Conversion failed"), subtitle: error.localizedDescription, tint: .red))
                }
            }
        }
    }
}
