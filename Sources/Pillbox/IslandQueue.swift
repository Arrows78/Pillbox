import Foundation
import AppKit
import SwiftUI
import WebKit

/// Islands arrive faster than they can be read: later ones wait their turn, an update of the one on screen
/// (same symbol and title, e.g. a volume bar) replaces it in place, and the backlog is capped.
struct ActivityQueue {
    private(set) var current: Activity?
    private(set) var pending: [Activity] = []
    static let cap = 4

    private static func same(_ a: Activity, _ b: Activity) -> Bool { a.title == b.title && a.symbol == b.symbol }

    /// True when the visible island changed. Importance decides the order: a high one jumps the queue and replaces a HUD
    /// on screen, a low one (volume, caps lock) is dropped when something else is showing rather than shown late.
    mutating func push(_ a: Activity) -> Bool {
        guard let c = current else { current = a; return true }
        if Self.same(c, a) { current = a; return true }
        if let i = pending.firstIndex(where: { Self.same($0, a) }) { pending[i] = a; return false }
        switch a.priority {
        case .low: return false
        case .high:
            if c.priority == .low { current = a; return true }
            pending.insert(a, at: 0)
            if pending.count > Self.cap { pending.remove(at: 1) }   // the oldest of the others goes
        case .normal:
            pending.append(a)
            if pending.count > Self.cap { pending.removeFirst() }   // the newest are kept
        }
        return false
    }

    mutating func advance() { current = pending.isEmpty ? nil : pending.removeFirst() }
    mutating func clear() { current = nil; pending = [] }
}

// MARK: Island theme
