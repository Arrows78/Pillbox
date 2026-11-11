import Foundation
import AppKit
import SQLite3
import SwiftUI

/// Reads the active Focus from Do Not Disturb's assertions file (needs Full Disk Access).
@MainActor
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()
    @Published private(set) var mode: String?
    private var timer: Timer?
    private var first = true
    static let path = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"

    nonisolated static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = (root["data"] as? [[String: Any]])?.compactMap({ $0["storeAssertionRecords"] as? [[String: Any]] }).flatMap({ $0 }),
              let id = records.compactMap({ ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }).first else { return nil }
        if id.hasSuffix(".default") || id.hasSuffix("donotdisturb") { return localized("Do Not Disturb") }
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        poll()
    }

    private func poll() {
        guard Defaults.bool("focusIsland", default: true), let d = FileManager.default.contents(atPath: Self.path) else { return }
        let new = Self.parse(d)
        defer { first = false }
        guard new != mode else { return }
        mode = new
        guard !first else { return }
        NotchModel.shared.show(Activity(symbol: new == nil ? "moon" : "moon.fill", title: new ?? localized("Focus off"), tint: new == nil ? .white : .purple, duration: 2.5))
    }
}

// MARK: Notification mirror
