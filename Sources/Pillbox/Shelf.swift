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

    /// Compresses files into a zip (or expands archives) with the system `ditto`.
    func zipOrUnzip(_ list: [ShelfItem]) {
        for item in list {
            let u = item.url
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            let out: URL
            if u.pathExtension.lowercased() == "zip" {
                out = u.deletingPathExtension()
                p.arguments = ["-x", "-k", u.path, out.path]
            } else {
                out = u.appendingPathExtension("zip")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", u.path, out.path]
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
            try? p.run()
        }
    }
}
