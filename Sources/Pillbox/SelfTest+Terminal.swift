import Foundation

/// Pure checks for the Terminal tab's look and session selection. No shell is started here.
extension SelfTest {
    static func terminalLook() {
        check("terminal: font size stays between 10 and 18, 12 by default", TerminalLook.clampedSize(4) == 10 && TerminalLook.clampedSize(12) == 12 && TerminalLook.clampedSize(40) == 18
              && Preferences.terminalFontSize.defaultValue == 12 && TerminalLook.defaultFontSize == 12)
        check("terminal: dark is the default theme, an unknown name falls back to dark", Preferences.terminalTheme.defaultValue == "dark"
              && TerminalTheme(rawValue: "light") == .light && (TerminalTheme(rawValue: "solarized") ?? .dark) == .dark)
        let a = UUID(), b = UUID(), c = UUID()
        check("terminal sessions: closing the selected one selects the next, or the previous at the end",
              TerminalSessions.selectionAfterClosing(order: [a, b, c], closed: b, selected: b) == c
              && TerminalSessions.selectionAfterClosing(order: [a, b, c], closed: c, selected: c) == b)
        check("terminal sessions: closing another one keeps the selection, and the last session leaves none",
              TerminalSessions.selectionAfterClosing(order: [a, b, c], closed: a, selected: b) == b
              && TerminalSessions.selectionAfterClosing(order: [a], closed: a, selected: a) == nil)
    }
}
