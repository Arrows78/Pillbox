import Foundation
import AppKit
import SwiftUI

struct CopyStack {
    private(set) var items: [String] = []
    static let cap = 20
    mutating func push(_ s: String) { items.append(s); if items.count > Self.cap { items.removeFirst() } }
    mutating func pop() -> String? { items.isEmpty ? nil : items.removeFirst() }
    mutating func clear() { items = [] }
}

@MainActor
final class CopyStackStore: ObservableObject {
    static let shared = CopyStackStore()
    @Published private(set) var stack = CopyStack()
    var enabled: Bool { UserDefaults.standard.bool(forKey: "copyStack") }

    func noteCopy(_ text: String) {
        guard enabled else { return }
        stack.push(text)
        NotchModel.shared.show(Activity(symbol: "square.stack.fill", title: localized("Stack: %d", stack.items.count), subtitle: String(text.prefix(40)), tint: .blue, duration: 1.2))
    }

    /// Pastes the oldest copy and removes it from the stack.
    func pasteNext() {
        guard let s = stack.pop() else { NotchModel.shared.show(Activity(symbol: "square.stack", title: "The copy stack is empty", duration: 1.5)); return }
        ClipboardService.shared.paste(ClipItem(text: s))
    }

    func clear() { stack.clear() }
}

// MARK: Calculation history
