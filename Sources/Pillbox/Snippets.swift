import SwiftUI
import Foundation
import AppKit

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
