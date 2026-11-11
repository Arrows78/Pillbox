import Foundation
import AppKit
import SwiftUI

struct CalcHistory {
    private(set) var entries: [String]
    static let cap = 10
    init(_ e: [String] = []) { entries = e }
    mutating func add(expression: String, result: String) {
        let line = "\(expression) = \(result)"
        entries.removeAll { $0 == line }
        entries.insert(line, at: 0)
        if entries.count > Self.cap { entries.removeLast() }
    }
    /// The result part of an entry, for copying it again.
    static func result(of entry: String) -> String { entry.components(separatedBy: " = ").last ?? entry }
}

@MainActor
enum CalcStore {
    static var history = CalcHistory(Store.load("calc.json", as: [String].self) ?? [])
    static func record(_ expr: String, _ result: String) { history.add(expression: expr, result: result); Store.save(history.entries, "calc.json") }
}

/// Recursive-descent evaluator: `+ - * /`, unary minus, parentheses and a trailing `%` (which divides by 100,
/// at the precedence of `*` and `/`). Returns nil for anything malformed.
struct MathParser {
    private let chars: [Character]
    private var i = 0
    init(_ chars: [Character]) { self.chars = chars }

    mutating func parse() -> Double? {
        guard let v = expression(), i == chars.count else { return nil }
        return v
    }

    private mutating func expression() -> Double? {
        guard var v = term() else { return nil }
        while i < chars.count, chars[i] == "+" || chars[i] == "-" {
            let op = chars[i]; i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = factor() else { return nil }
        while i < chars.count, "*/%".contains(chars[i]) {
            let op = chars[i]; i += 1
            if op == "%" { v /= 100; continue }
            guard let r = factor() else { return nil }
            v = op == "*" ? v * r : v / r
        }
        return v
    }

    private mutating func factor() -> Double? {
        guard i < chars.count else { return nil }
        if chars[i] == "-" { i += 1; return factor().map { -$0 } }
        if chars[i] == "(" {
            i += 1
            guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
            i += 1; return v
        }
        let start = i
        while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
        return start < i ? Double(String(chars[start..<i])) : nil
    }
}
