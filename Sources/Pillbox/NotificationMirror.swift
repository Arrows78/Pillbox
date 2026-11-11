import Foundation
import AppKit
import SQLite3
import SwiftUI

struct NotificationItem: Identifiable {
    let id: Int64
    let app: String
    let title: String
    let body: String
    let date: Date
    /// The title alone, without the subtitle: the name a contact is looked up by.
    var sender = ""
}

/// What reading Notification Center's database gave.
enum NotificationRead {
    case items([NotificationItem])
    case noAccess   // the database cannot be opened (no Full Disk Access)
    case failed     // it opened, but the query did not work
}

/// Reads Notification Center's database (needs Full Disk Access). Read-only; nothing is stored or sent.
enum NotificationReader {
    static let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"

    static func parse(_ blob: Data) -> (app: String, title: String, body: String, sender: String)? {
        guard let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any], let req = plist["req"] as? [String: Any] else { return nil }
        let title = [req["titl"], req["subt"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
        return (plist["app"] as? String ?? "", title, req["body"] as? String ?? "", req["titl"] as? String ?? "")
    }

    /// nil when the rows cannot be read: no database access, or a failed query.
    static func read(limit: Int = 30, path: String = path) -> [NotificationItem]? {
        guard case .items(let items) = load(limit: limit, path: path) else { return nil }
        return items
    }

    static func load(limit: Int = 30, path: String = path) -> NotificationRead {
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { sqlite3_close(db); return .noAccess }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        let sql = "SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r LEFT JOIN app a ON r.app_id = a.app_id ORDER BY r.delivered_date DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return .failed }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(limit))
        var out: [NotificationItem] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            guard let p = parse(data) else { continue }
            let ident = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? p.app
            out.append(NotificationItem(id: sqlite3_column_int64(st, 0), app: ident, title: p.title, body: p.body,
                                        date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 3)), sender: p.sender))
        }
        return .items(out)
    }
}

@MainActor
final class NotificationMirror: ObservableObject {
    static let shared = NotificationMirror()
    @Published private(set) var items: [NotificationItem]?
    /// The database opened but could not be read: a different problem from missing Full Disk Access.
    @Published private(set) var queryFailed = false
    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let result = NotificationReader.load()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .items(let found): self.items = found; self.queryFailed = false
                    case .noAccess: self.items = nil; self.queryFailed = false
                    case .failed: self.items = nil; self.queryFailed = true
                    }
                }
            }
        }
    }
}

// MARK: Call in progress
