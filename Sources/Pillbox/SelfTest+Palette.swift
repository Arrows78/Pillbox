import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func math() {
        check("palette math precedence", PaletteModel.evaluate("2+3*4") == "14", PaletteModel.evaluate("2+3*4") ?? "nil")
        check("palette math division", PaletteModel.evaluate("10/4") == "2.5", PaletteModel.evaluate("10/4") ?? "nil")
        check("palette math parentheses", PaletteModel.evaluate("(1+2)*3") == "9", PaletteModel.evaluate("(1+2)*3") ?? "nil")
        check("palette math rejects text", PaletteModel.evaluate("abc") == nil && PaletteModel.evaluate("42") == nil)
        check("palette math rejects code", PaletteModel.evaluate("FUNCTION(1,'x')+1") == nil)
    }

    static func formatting() {
        check("timer format minutes", TimerService.format(65) == "01:05", TimerService.format(65))
        check("timer format hours", TimerService.format(3725) == "1:02:05", TimerService.format(3725))
        check("token shortening", AIUsageService.short(999) == "999" && AIUsageService.short(12_400) == "12k" && AIUsageService.short(2_500_000) == "2.5M")
    }

    static func timer() {
        let t = TimerService()
        t.mode = .countdown; t.countdownMinutes = 1
        check("countdown starts at its length", Int(t.seconds) == 60, "\(t.seconds)")
        t.start()
        check("countdown runs", t.running)
        t.pause()
        let frozen = t.seconds
        check("pause keeps the remaining time", !t.running && frozen > 58 && frozen <= 60, "\(frozen)")
        t.reset()
        check("reset restores the length", Int(t.seconds) == 60 && !t.isActive)
        t.mode = .stopwatch
        check("stopwatch starts at zero", t.seconds == 0)
    }

    static func palette() {
        let m = PaletteModel()
        check("palette lists every tab", Tab.allCases.allSatisfy { t in m.commands.contains { $0.title.contains(L("Go to %@", t.title)) } })
        m.query = String(L("Snap window: %@", "").prefix(4))
        check("palette filters by query", !m.commands.isEmpty && m.commands.allSatisfy { $0.title.localizedCaseInsensitiveContains(m.query) }, m.query)
        m.query = "2+2*5"
        check("palette answers maths first", m.commands.first?.title.hasPrefix("= 12") == true, m.commands.first?.title ?? "none")
        m.query = "zzzz-no-such-command"
        check("palette offers only a web search for nonsense", m.commands.count == 1 && m.commands[0].title.contains("zzzz-no-such-command"), "\(m.commands.map(\.title))")
    }

    /// Palette maths must reject bad input instead of throwing; it also handles unary minus and percent.
    static func paletteMath() {
        // Palette math must never throw: NSExpression raised an exception on "5+" and crashed the app while typing.
        for bad in ["5+", "(2+3", "2+3)", "*3", "5 6+1", "1..2+3", "()+1", "5%3", "--"] {
            check("palette math: \"\(bad)\" is rejected, not a crash", PaletteModel.evaluate(bad) == nil, PaletteModel.evaluate(bad) ?? "nil")
        }
        check("palette math: unary minus and percent", PaletteModel.evaluate("-2+10") == "8" && PaletteModel.evaluate("200*10%") == "20", "\(PaletteModel.evaluate("-2+10") ?? "nil") \(PaletteModel.evaluate("200*10%") ?? "nil")")
    }
}
