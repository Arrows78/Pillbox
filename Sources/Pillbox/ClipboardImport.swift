import AppKit
import SQLite3

/// Opens a private copy of another app's SQLite database, with its -wal file. Recent rows live in the WAL, which an
/// immutable read skips, so the copy is what gets read. The caller closes `db` and deletes `folder`.
enum SQLiteSnapshot {
    nonisolated static func open(_ path: String) throws -> (db: OpaquePointer, folder: URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-db-\(UUID().uuidString)", isDirectory: true)
        let copy = folder.appendingPathComponent("copy.sqlite")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: path, toPath: copy.path)
            if FileManager.default.fileExists(atPath: path + "-wal") { try FileManager.default.copyItem(atPath: path + "-wal", toPath: copy.path + "-wal") }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw ClipboardImport.ReadFailure.unreadable
        }
        var db: OpaquePointer?
        // A writable open lets SQLite create its -shm index next to the copy; the copy is ours and is deleted afterwards.
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle = db else {
            sqlite3_close(db); try? FileManager.default.removeItem(at: folder)
            throw ClipboardImport.ReadFailure.unreadable
        }
        return (handle, folder)
    }
}

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

    /// Why the history could not be read: the files are not accessible, or the database layout is not the one Pillbox knows.
    enum ReadFailure: Error { case unreadable, changed }

    /// Items found in the database: text, date and whether the source had it pinned.
    /// The database is read from a copy (see SQLiteSnapshot); the source files are never opened or changed.
    static func read(_ source: Source, path: String? = nil) throws -> [(text: String, date: Date, pinned: Bool)] {
        let snapshot = try SQLiteSnapshot.open(path ?? source.path)
        let db = snapshot.db
        defer { sqlite3_close(db); try? FileManager.default.removeItem(at: snapshot.folder) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, source.query, -1, &st, nil) == SQLITE_OK else { throw ReadFailure.changed }
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
    /// Returns how many imported items the history kept after the cap.
    @MainActor static func merge(_ items: [(text: String, date: Date, pinned: Bool)], into clip: ClipboardService) -> Int {
        var added: Set<UUID> = []
        for i in items.reversed() {
            let t = i.text
            guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !clip.items.contains(where: { $0.text == t }) else { continue }
            var item = ClipItem(text: t); item.date = i.date; item.pinned = i.pinned
            clip.items.append(item); added.insert(item.id)
        }
        clip.trim()
        return clip.items.filter { added.contains($0.id) }.count
    }

    @MainActor static func run(_ source: Source) {
        guard source.installed else {
            NotchModel.shared.show(Activity(symbol: "doc.on.clipboard", title: localized("No %@ history on this Mac", source.name), tint: .orange)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let items: [(text: String, date: Date, pinned: Bool)]
            do { items = try read(source) } catch {
                let changed = (error as? ReadFailure) == .changed
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if changed {
                            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not read %@'s history", source.name), subtitle: localized("%@ changed its database format", source.name), tint: .orange, duration: 8))
                        } else {
                            NotchModel.shared.show(Activity(symbol: "lock.fill", title: localized("Could not read %@'s history", source.name), subtitle: localized("macOS keeps other apps' data private: allow Full Disk Access"), tint: .orange,
                                                            actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.fullDisk) }, duration: 8))
                        }
                    }
                }
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let n = merge(items, into: ClipboardService.shared)
                    ClipboardService.shared.save()
                    NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: localized("Imported %d item(s) from %@", n, source.name), tint: .green))
                }
            }
        }
    }
}
