import AppKit
import SQLite3

/// Brings the text history of another clipboard manager into Pillbox (Maccy, Alfred). Read-only: their files are never changed.
enum ClipboardImport {
    enum Source: String, CaseIterable, Identifiable {
        case maccy, alfred
        var id: String { rawValue }
        var name: String { self == .maccy ? "Maccy" : "Alfred" }
        var path: String {
            switch self {
            case .maccy: NSHomeDirectory() + "/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
            case .alfred: NSHomeDirectory() + "/Library/Application Support/Alfred/Databases/clipboard.alfdb"
            }
        }
        var installed: Bool { FileManager.default.fileExists(atPath: path) }
        /// Text items, newest first; Core Data stores dates as seconds since 2001.
        var query: String {
            switch self {
            case .maccy: "SELECT c.ZVALUE, i.ZLASTCOPIEDAT, i.ZPIN FROM ZHISTORYITEMCONTENT c JOIN ZHISTORYITEM i ON c.ZITEM = i.Z_PK WHERE c.ZTYPE = 'public.utf8-plain-text' ORDER BY i.ZLASTCOPIEDAT DESC LIMIT 300"
            case .alfred: "SELECT item, ts, NULL FROM clipboard WHERE dataType = 0 ORDER BY ts DESC LIMIT 300"
            }
        }
    }

    enum Outcome { case imported(Int), empty, unreadable, missing }

    /// Items found in the database: text, date and whether the source had it pinned.
    static func read(_ source: Source, path: String? = nil) -> [(text: String, date: Date, pinned: Bool)]? {
        let file = path ?? source.path
        guard FileManager.default.fileExists(atPath: file) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(file)?mode=ro&immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, source.query, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        var out: [(String, Date, Bool)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let text: String
            if sqlite3_column_type(st, 0) == SQLITE_BLOB, let b = sqlite3_column_blob(st, 0) {
                text = String(decoding: Data(bytes: b, count: Int(sqlite3_column_bytes(st, 0))), as: UTF8.self)
            } else if let t = sqlite3_column_text(st, 0) { text = String(cString: t) } else { continue }
            let pinned = sqlite3_column_type(st, 2) == SQLITE_TEXT || (sqlite3_column_type(st, 2) == SQLITE_INTEGER && sqlite3_column_int(st, 2) != 0)
            out.append((text, Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 1)), pinned))
        }
        return out
    }

    /// Merges `items` into the history: texts already there keep their place, blank ones are skipped, the cap applies after.
    @MainActor static func merge(_ items: [(text: String, date: Date, pinned: Bool)], into clip: ClipboardService) -> Int {
        var n = 0
        for i in items.reversed() {
            let t = i.text
            guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !clip.items.contains(where: { $0.text == t }) else { continue }
            var item = ClipItem(text: t); item.date = i.date; item.pinned = i.pinned
            clip.items.append(item); n += 1
        }
        clip.trim()
        return n
    }

    @MainActor static func run(_ source: Source) {
        guard source.installed else {
            NotchModel.shared.show(Activity(symbol: "doc.on.clipboard", title: L("No %@ history on this Mac", source.name), tint: .orange)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let items = read(source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let items else {
                        NotchModel.shared.show(Activity(symbol: "lock.fill", title: L("Could not read %@'s history", source.name), subtitle: "macOS keeps other apps' data private: allow Full Disk Access", tint: .orange,
                                                        actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.fullDisk) }, duration: 8))
                        return
                    }
                    let n = merge(items, into: ClipboardService.shared)
                    ClipboardService.shared.persist()
                    NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: L("Imported %d item(s) from %@", n, source.name), tint: .green))
                }
            }
        }
    }
}
