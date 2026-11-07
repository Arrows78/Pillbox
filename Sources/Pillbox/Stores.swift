import AppKit

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var date = Date()
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()
    @Published var notes: [Note] = Store.load("notes.json", as: [Note].self) ?? []
    @Published var draft = ""

    func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        notes.insert(Note(text: t), at: 0); draft = ""; save()
    }
    func toggle(_ n: Note) { if let i = notes.firstIndex(of: n) { notes[i].done.toggle(); save() } }
    func remove(_ n: Note) { notes.removeAll { $0.id == n.id }; save() }
    func clearDone() { notes.removeAll(where: \.done); save() }
    func save() { Store.save(notes, "notes.json") }
}

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
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        NotchModel.shared.collapse()
    }
    private func save() { Store.save(paths, "launcher.json") }
}

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var text: String
}

/// Reusable text, pasted from the clipboard tab or the command palette.
@MainActor
final class SnippetsStore: ObservableObject {
    static let shared = SnippetsStore()
    @Published var snippets: [Snippet] = Store.load("snippets.json", as: [Snippet].self) ?? []
    @Published var draftName = ""
    @Published var draftText = ""

    func add() {
        let n = draftName.trimmingCharacters(in: .whitespacesAndNewlines), t = draftText
        guard !n.isEmpty, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snippets.append(Snippet(name: n, text: t)); draftName = ""; draftText = ""; save()
    }
    func remove(_ s: Snippet) { snippets.removeAll { $0.id == s.id }; save() }
    func paste(_ s: Snippet) { ClipboardService.shared.paste(ClipItem(text: s.text)) }
    private func save() { Store.save(snippets, "snippets.json") }
}
