import SwiftUI
import Foundation
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
    func toggle(_ n: Note) { if let i = notes.firstIndex(where: { $0.id == n.id }) { notes[i].done.toggle(); save() } }
    func remove(_ n: Note) { notes.removeAll { $0.id == n.id }; save() }
    func clearDone() { notes.removeAll(where: \.done); save() }
    func save() { Store.save(notes, "notes.json") }
}

struct NotesTab: View {
    @ObservedObject var store = NotesStore.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Design.gap) {
            HStack(spacing: Design.gap) {
                TextField("Jot something down…", text: $store.draft).pillField().focused($focused)
                    .onSubmit { store.add() }
                if store.notes.contains(where: \.done) { Button("Clear done") { store.clearDone() }.buttonStyle(PillButtonStyle()).fixedSize() }
            }
            .keepsIslandOpen(while: focused, in: model)
            if store.notes.isEmpty {
                EmptyState(symbol: "note.text", title: "No notes yet", message: "Quick notes and to-dos stay here until you check them off")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.notes) { n in
                            HStack(spacing: 8) {
                                Button { store.toggle(n) } label: { Image(systemName: n.done ? "checkmark.circle.fill" : "circle").foregroundStyle(n.done ? Color.yellow : Design.secondary) }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(n.done ? "Mark as not done" : "Mark as done"))
                                Text(n.text).strikethrough(n.done).foregroundStyle(n.done ? Design.secondary : .white).lineLimit(2)
                                Spacer(minLength: 0)
                                IconButton(symbol: "trash", label: localized("Delete")) { store.remove(n) }
                            }
                            .font(.system(size: 12)).padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 3).rowCard()
                            .contextMenu {
                                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.text, forType: .string) }
                                Button(LocalizedStringKey(n.done ? "Mark as not done" : "Mark as done")) { store.toggle(n) }
                                Button("Delete", role: .destructive) { store.remove(n) }
                            }
                        }
                    }
                }
            }
        }
    }
}
