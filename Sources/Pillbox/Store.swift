import AppKit
import Foundation
import SwiftUI

enum Store {
    static let dir: URL = {
        // PILLBOX_DATA_DIR lets the self-test run against a throwaway folder.
        let u = ProcessInfo.processInfo.environment["PILLBOX_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Pillbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(T.self, from: d) { return value }
        // Unreadable file: keep a copy so the next save does not overwrite the user's data with an empty default.
        try? FileManager.default.removeItem(at: url.appendingPathExtension("broken"))
        try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("broken"))
        return nil
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        if let d = try? JSONEncoder().encode(value) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }
}
