import Foundation
import OSLog

/// Pillbox's log, by area. Entries go to the unified log (Console.app) and the About pane can copy the last hour of them.
/// Only what helps a bug report: never the content of the clipboard, the shelf, a message or a key.
enum Log {
    static let subsystem = "dev.labs.pillbox"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let update = Logger(subsystem: subsystem, category: "update")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let api = Logger(subsystem: subsystem, category: "api")

    /// The last `since` seconds of this process's log lines, one per line, oldest first. Empty when the store cannot be read.
    static func recentText(since: TimeInterval = 3600) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return "" }
        let start = store.position(date: Date().addingTimeInterval(-since))
        guard let entries = try? store.getEntries(at: start, matching: NSPredicate(format: "subsystem == %@", subsystem)) else { return "" }
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(entry.date.formatted(date: .numeric, time: .standard)) [\(entry.category)] \(entry.composedMessage)")
        }
        return lines.joined(separator: "\n")
    }
}
