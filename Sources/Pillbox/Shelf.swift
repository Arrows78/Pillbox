import AppKit

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var path: String
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
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

    func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) }; selection.subtract(ids); save() }
    func clear() { items.removeAll(); selection.removeAll(); save() }
    private func save() { Store.save(items, "shelf.json") }

    var selected: [ShelfItem] { items.filter { selection.contains($0.id) } }

    func airDrop(_ list: [ShelfItem]) {
        let urls = list.map(\.url)
        guard !urls.isEmpty, let svc = NSSharingService(named: .sendViaAirDrop), svc.canPerform(withItems: urls) else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "AirDrop unavailable", tint: .orange))
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
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(list.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// "3 items · 2 selected", the shelf's header line.
    nonisolated static func summary(count: Int, selected: Int) -> String {
        let n = count == 1 ? L("1 item") : L("%lld items", count)
        return selected > 0 ? n + " · " + L("%lld selected", selected) : n
    }

    /// A sibling URL that does not exist yet ("name", "name 2", "name 3"…), so nothing is ever overwritten.
    nonisolated static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension(), ext = url.pathExtension
        var n = 2
        while true {
            let candidate = (ext.isEmpty ? URL(fileURLWithPath: base.path + " \(n)") : URL(fileURLWithPath: base.path + " \(n)").appendingPathExtension(ext))
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// Compresses files into a zip (or expands archives into a new folder) with the system `ditto`.
    func zipOrUnzip(_ list: [ShelfItem]) {
        for item in list {
            let u = item.url
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            let out: URL
            if u.pathExtension.lowercased() == "zip" {
                out = Self.uniqueURL(u.deletingPathExtension())
                p.arguments = ["-x", "-k", u.path, out.path]
            } else {
                out = Self.uniqueURL(u.appendingPathExtension("zip"))
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
                            NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: "Archive failed", tint: .red))
                        }
                    }
                }
            }
            do { try p.run() } catch { NotchModel.shared.show(Activity(symbol: "xmark.octagon", title: "Archive failed", tint: .red)) }
        }
    }
}
