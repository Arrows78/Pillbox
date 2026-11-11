import Foundation
import AppKit
import ApplicationServices

/// Short names for palette commands. Kept by the command's stable English title (`PaletteCommand.key`), so an alias
/// survives a change of language and the commands whose title changes ("Mute microphone" / "Unmute microphone").
enum PaletteAliases {
    static func set(_ alias: String, for key: String) {
        guard !key.isEmpty else { return }
        var all = Preferences.paletteAliases.value
        let clean = clean(alias)
        all[key] = clean.isEmpty ? nil : clean
        UserDefaults.standard.set(all, forKey: Preferences.paletteAliases.key)
    }

    /// Trimmed text, so a blank field removes the alias.
    static func clean(_ alias: String) -> String { alias.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Installed applications, for "type an app name, press Enter". Scanned once, then again after a minute so a new install shows.
@MainActor
enum PaletteApps {
    struct App: Equatable { let name: String; let url: URL }

    static let folders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    private static var cache: (date: Date, apps: [App])?

    static var installed: [App] {
        if let cache, Date().timeIntervalSince(cache.date) < 60 { return cache.apps }
        let apps = scan(folders)
        cache = (Date(), apps)
        return apps
    }

    /// The `.app` bundles in `folders`, and in the folders inside them one level down (Utilities), by name.
    static func scan(_ folders: [String]) -> [App] {
        let fm = FileManager.default
        var seen = Set<String>(), out: [App] = []
        func visit(_ dir: URL, depth: Int) {
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                if url.pathExtension == "app" {
                    let name = url.deletingPathExtension().lastPathComponent
                    if seen.insert(name).inserted { out.append(App(name: name, url: url)) }
                } else if depth == 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(url, depth: 1)
                }
            }
        }
        for f in folders { visit(URL(fileURLWithPath: f), depth: 0) }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The apps whose names match `query`, best match first, at most `limit`.
    static func matches(_ query: String, in apps: [App], limit: Int = 8) -> [App] {
        guard !query.isEmpty else { return [] }
        return apps.compactMap { a in FuzzyMatch.score(query, in: a.name).map { (a, $0) } }
            .sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

/// Files by name through Spotlight, for "f " then the name. NSMetadataQuery answers asynchronously, so the palette
/// gets its rows in a callback once the query has gathered (or after a short wait).
@MainActor
final class FileSearch {
    static let shared = FileSearch()
    static let limit = 8
    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var timeout: DispatchWorkItem?

    /// The predicate for `text`: every word must appear in the file name.
    static func predicate(for text: String) -> NSPredicate {
        let words = text.split(separator: " ").map(String.init)
        return NSCompoundPredicate(andPredicateWithSubpredicates: words.map {
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0)
        })
    }

    func search(_ text: String, done: @escaping ([URL]) -> Void) {
        cancel()
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.predicate = Self.predicate(for: text)
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        query = q
        let finish = { [weak self] in
            guard let self, self.query === q else { return }
            let urls = q.results.prefix(Self.limit).compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
            self.cancel()
            done(urls.map { URL(fileURLWithPath: $0) })
        }
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
            MainActor.assumeIsolated { finish() }
        }
        let work = DispatchWorkItem { finish() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        q.start()
    }

    func cancel() {
        timeout?.cancel(); timeout = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        query?.stop(); query = nil
    }
}

/// Open windows, for "w " then the name. The window titles need the Accessibility permission that window snapping
/// already asks for; without it each running app is listed by its name only.
@MainActor
enum PaletteWindows {
    /// The row text: the app name, then the window title when there is one that differs from it.
    static func label(app: String, window: String?) -> String {
        guard let w = window?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty, w != app else { return app }
        return "\(app) — \(w)"
    }

    static func rows() -> [PaletteCommand] {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
        var out: [PaletteCommand] = []
        for app in apps {
            let name = app.localizedName ?? app.bundleIdentifier ?? "\(app.processIdentifier)"
            let windows = AXIsProcessTrusted() ? windowTitles(of: app.processIdentifier) : []
            if windows.isEmpty {
                out.append(PaletteCommand(localized: name, symbol: "macwindow", category: .windows) { app.activate() })
            }
            for (window, title) in windows {
                out.append(PaletteCommand(localized: label(app: name, window: title), symbol: "macwindow", category: .windows) {
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    app.activate()
                })
            }
        }
        return out
    }

    /// The app's windows that have a title, through Accessibility. A hung app waits at most AXWindow.messagingTimeout.
    private static func windowTitles(of pid: pid_t) -> [(AXUIElement, String)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, AXWindow.messagingTimeout)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }
        return windows.compactMap { w in
            var t: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
            guard let title = t as? String, !title.isEmpty else { return nil }
            return (w, title)
        }
    }
}
