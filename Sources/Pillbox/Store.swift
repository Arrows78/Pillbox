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
    /// The schema each file is written with. Files written before versions existed have none and are read as version 1.
    /// When a file's shape changes: raise its version here, and add the step to `migrate`.
    static let versions: [String: Int] = [:]
    static let currentDefault = 1

    /// Brings the file bytes of `name` from `version` to the current schema. Nothing has changed shape yet, so no step runs.
    static func migrate(_ name: String, from version: Int, data: Data) -> Data {
        data
    }

    private struct VersionOnly: Decodable { let version: Int }

    private struct Versioned<T: Decodable>: Decodable {
        let version: Int
        let data: T
    }

    private struct Envelope<T: Encodable>: Encodable {
        let version: Int
        let data: T
    }

    static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        let url = dir.appendingPathComponent(name)
        guard let d = try? Data(contentsOf: url) else { return nil }
        if let version = (try? JSONDecoder().decode(VersionOnly.self, from: d))?.version {
            let current = migrate(name, from: version, data: d)
            if let versioned = try? JSONDecoder().decode(Versioned<T>.self, from: current) { return versioned.data }
        }
        if let value = try? JSONDecoder().decode(T.self, from: d) { return value }   // written before versions
        // Unreadable file: keep a copy so the next save does not overwrite the user's data with an empty default.
        try? FileManager.default.removeItem(at: url.appendingPathExtension("broken"))
        try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("broken"))
        return nil
    }
    static func save<T: Encodable>(_ value: T, _ name: String) {
        let envelope = Envelope(version: versions[name] ?? currentDefault, data: value)
        if let d = try? JSONEncoder().encode(envelope) { try? d.write(to: dir.appendingPathComponent(name), options: .atomic) }
    }
}
