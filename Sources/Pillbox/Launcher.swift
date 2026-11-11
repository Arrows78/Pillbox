import SwiftUI
import Foundation
import AppKit

@MainActor
final class LauncherStore: ObservableObject {
    static let shared = LauncherStore()
    @Published var paths: [String] = Store.load("launcher.json", as: [String].self) ?? []

    func add() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NotchModel.shared.pinnedOpen = true
        p.begin { r in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NotchModel.shared.pinnedOpen = false
                    guard r == .OK else { return }
                    for u in p.urls where !self.paths.contains(u.path) { self.paths.append(u.path) }
                    self.save()
                }
            }
        }
    }
    func remove(_ path: String) { paths.removeAll { $0 == path }; save() }
    /// Dropping an icon onto another makes it take that icon's slot.
    func move(_ path: String, onto target: String) {
        guard path != target, let from = paths.firstIndex(of: path), let to = paths.firstIndex(of: target) else { return }
        paths.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to); save()
    }
    func launch(_ path: String) {
        let url = URL(fileURLWithPath: path)
        AppLauncher.open(url, named: url.deletingPathExtension().lastPathComponent)
    }
    private func save() { Store.save(paths, "launcher.json") }
}

/// Opens an app and collapses the island. A moved or deleted app (`url` nil or failing) shows a message instead of failing silently.
@MainActor
enum AppLauncher {
    static func open(_ url: URL?, named name: String) {
        guard let url else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not open the app"), subtitle: name, tint: .orange))
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not open the app"), subtitle: name, tint: .orange))
                }
            }
        }
        NotchModel.shared.collapse()
    }
}
