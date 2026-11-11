import AppKit
import Foundation

/// Apps whose copies are not recorded in the clipboard history. Copies are skipped while one of them is frontmost.
enum ClipboardExclusions {
    static let key = "clipboardExcludedApps"
    /// Bundle IDs of the apps the user excluded.
    static var ids: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    /// The last app that was not Pillbox, set by AppDelegate. Settings runs inside Pillbox, so this is the app the user was in.
    @MainActor static var lastOtherAppID: String?

    /// True when a copy made while `bundleID` is frontmost must not be recorded.
    static func isExcluded(_ bundleID: String?, in list: [String]) -> Bool {
        guard let bundleID else { return false }
        return list.contains(bundleID)
    }

    /// The list with `bundleID` appended, without duplicates.
    static func adding(_ bundleID: String, to list: [String]) -> [String] {
        list.contains(bundleID) ? list : list + [bundleID]
    }

    static func removing(_ bundleID: String, from list: [String]) -> [String] {
        list.filter { $0 != bundleID }
    }

    static func set(_ list: [String]) {
        UserDefaults.standard.set(list, forKey: key)
    }

    /// Adds the app the user was in: the frontmost app, or the last other app when Pillbox itself is in front (Settings).
    @MainActor static func addFrontmost() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let id = front == Bundle.main.bundleIdentifier ? lastOtherAppID : front
        guard let id, id != Bundle.main.bundleIdentifier else { return }
        set(adding(id, to: ids))
    }
}

/// Recognises values that look like a secret: an API key or token, or a payment card number.
enum ClipboardSecrets {
    /// Common prefixes of API keys and tokens.
    static let prefixes = ["sk-", "ghp_", "gho_", "github_pat_", "AKIA", "xoxb-", "xoxp-", "xoxa-", "xoxr-", "AIza", "glpat-"]

    static func isSecret(_ text: String) -> Bool {
        isToken(text) || isCardNumber(text)
    }

    /// A single long token with a known prefix and high entropy.
    static func isToken(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 20, t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        guard prefixes.contains(where: { t.hasPrefix($0) }) else { return false }
        return entropy(t) >= 3.0
    }

    /// 13 to 19 digits, optionally grouped with spaces or dashes, that pass the Luhn check.
    static func isCardNumber(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.range(of: #"^[0-9][0-9 -]*[0-9]$"#, options: .regularExpression) != nil else { return false }
        let digits = t.filter(\.isNumber)
        return (13...19).contains(digits.count) && luhn(digits)
    }

    /// The Luhn checksum of a string of digits.
    static func luhn(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, !values.isEmpty else { return false }
        var sum = 0
        for (i, d) in values.reversed().enumerated() {
            if i % 2 == 1 {
                let doubled = d * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += d
            }
        }
        return sum % 10 == 0
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
    }

    /// The ids of secret, unpinned items copied at least `minutes` ago. Zero means secrets are kept until removed by hand.
    static func expiredIDs(_ items: [ClipItem], minutes: Int, now: Date) -> [UUID] {
        guard minutes > 0 else { return [] }
        let limit = Double(minutes) * 60
        return items.filter { $0.secret == true && !$0.pinned && now.timeIntervalSince($0.date) >= limit }.map(\.id)
    }
}
