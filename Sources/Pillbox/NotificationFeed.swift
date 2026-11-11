import Foundation
import AppKit
import SwiftUI
import WebKit

/// New Notification Center entries shown as islands, with the app's own wording. The database is only read while
/// one of its features is on: mirroring new notifications (opt-in), or verification codes (on by default).
@MainActor
final class NotificationFeed {
    static let shared = NotificationFeed()
    private var lastID: Int64?
    private var timer: Timer?

    nonisolated static let codeIslandKey = "codeIsland"

    /// Items newer than `after`, oldest first.
    nonisolated static func fresh(_ items: [NotificationItem], after: Int64) -> [NotificationItem] {
        items.filter { $0.id > after }.sorted { $0.id < $1.id }
    }

    /// A 4 to 8 digit verification code in a message, when the text talks about a code (or is nothing but the code).
    nonisolated static func verificationCode(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil { return t }
        let keywords = ["code", "verification", "verify", "otp", "passcode", "pin", "2fa", "one-time", "mot de passe", "código", "codice"]
        // Whole words only: "pin" must not match "shipping" or "pinned".
        guard keywords.contains(where: { t.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil }) else { return nil }
        guard let r = t.range(of: #"(?<![\d.,])\d{3}[ -]?\d{3}(?![\d.,])|(?<![\d.,])\d{4,8}(?![\d.,])"#, options: .regularExpression) else { return nil }
        return t[r].filter(\.isNumber)
    }

    func start() {
        timer = PowerGate.timer(every: 5) { [weak self] in
            let codes = UserDefaults.standard.object(forKey: Self.codeIslandKey) as? Bool ?? true
            guard UserDefaults.standard.bool(forKey: "notificationIsland") || codes else { MainActor.assumeIsolated { self?.lastID = nil }; return }
            DispatchQueue.global(qos: .utility).async {
                let items = NotificationReader.read(limit: 10)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(items) } }
            }
        }
    }

    private func handle(_ items: [NotificationItem]?) {
        guard let items else { return }
        defer { lastID = max(lastID ?? 0, items.map(\.id).max() ?? 0) }
        guard let last = lastID else { return }   // first read is only a baseline
        let mirror = UserDefaults.standard.bool(forKey: "notificationIsland"), codes = UserDefaults.standard.object(forKey: Self.codeIslandKey) as? Bool ?? true
        for n in Self.fresh(items, after: last).suffix(3) {
            if codes, let code = Self.verificationCode(in: n.body) ?? Self.verificationCode(in: n.title) {
                NotchModel.shared.show(Activity(symbol: "key.fill", title: localized("Code %@", code), subtitle: n.title.isEmpty ? n.app : n.title, tint: .green,
                                                actionTitle: "Copy", action: { TextCopy.copy(code) }, duration: 12))
            } else if mirror, !NotificationMute.isMuted(n.app) {
                NotchModel.shared.show(Activity(symbol: "bell.fill", title: n.title.isEmpty ? n.app : n.title, subtitle: n.body.isEmpty ? nil : String(n.body.prefix(90)), tint: .yellow, duration: 5))
            }
        }
    }
}
