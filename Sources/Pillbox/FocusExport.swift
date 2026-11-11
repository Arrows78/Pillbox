import AppKit

/// The focus sessions per day, as a CSV file for a spreadsheet, and the sounds the timer can end with.
enum FocusExport {
    /// The sounds of macOS the timer can play when a session ends.
    static let sounds = ["Glass", "Ping", "Hero", "Submarine", "Basso", "Tink"]

    /// Header and one row per day, oldest first: `date,focus_sessions`.
    static func csv(_ sessions: [String: Int]) -> String {
        let rows = sessions.sorted { $0.key < $1.key }.map { "\($0.key),\($0.value)" }
        return (["date,focus_sessions"] + rows).joined(separator: "\n") + "\n"
    }

    /// Asks where to save the CSV, then writes the focus sessions of every day.
    @MainActor static func save(_ sessions: [String: Int]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Pillbox focus sessions.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try csv(sessions).write(to: url, atomically: true, encoding: .utf8)
            NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: localized("Focus sessions exported"), tint: .green))
        } catch {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: localized("Could not export the focus sessions"), tint: .orange))
        }
    }
}
