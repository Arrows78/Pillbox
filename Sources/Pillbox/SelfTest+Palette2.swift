import AppKit

extension SelfTest {
    /// The palette's prefixes, aliases, app and window matching, unit conversions and shortcut labels. Pure parsing and
    /// matching only: nothing here opens an app, reads a file or asks for a permission.
    static func paletteSources() {
        check("palette prefix: f reads files", PalettePrefix("f report") == .files("report"))
        check("palette prefix: f with nothing after it", PalettePrefix("f ") == .files(""))
        check("palette prefix: f without a space is an ordinary query", PalettePrefix("fish") == .none && PalettePrefix("f") == .none)
        check("palette prefix: w reads windows", PalettePrefix("w safari") == .windows("safari"))
        check("palette prefix: an empty w lists every window", PalettePrefix("w ") == .windows(""))
        check("palette prefix: leading spaces do not hide a prefix", PalettePrefix("  > mute") == .commands("mute") && PalettePrefix(" f  x") == .files("x"))

        let apps = ["Safari", "Calendar", "Slack"].map { PaletteApps.App(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app")) }
        check("apps: the letters of a name, in order", PaletteApps.matches("saf", in: apps).map(\.name) == ["Safari"])
        check("apps: nothing for an empty query", PaletteApps.matches("", in: apps).isEmpty)
        check("apps: at most eight", PaletteApps.matches("a", in: (0..<12).map { PaletteApps.App(name: "App\($0)a", url: URL(fileURLWithPath: "/x")) }).count == 8)

        check("windows: the app name alone without a window title", PaletteWindows.label(app: "Safari", window: nil) == "Safari" && PaletteWindows.label(app: "Safari", window: "  ") == "Safari")
        check("windows: a window title follows the app name", PaletteWindows.label(app: "Safari", window: "Apple") == "Safari — Apple")
        check("windows: a title equal to the app name is not repeated", PaletteWindows.label(app: "Notes", window: "Notes") == "Notes")

        let key = Preferences.paletteAliases.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        check("aliases: a blank alias is trimmed to nothing", PaletteAliases.clean("   ").isEmpty && PaletteAliases.clean(" mute ") == "mute")
        let cmd = PaletteCommand(title: "Turn keep awake on", symbol: "cup.and.saucer.fill", key: "Turn keep awake on") {}
        check("aliases: a command without an alias is not found by one", PaletteModel.ranked([cmd], "caffeine").isEmpty)
        PaletteAliases.set("caffeine", for: cmd.key)
        check("aliases: stored by the command's stable key", Preferences.paletteAliases.value[cmd.key] == "caffeine")
        check("aliases: the alias finds its command", PaletteModel.ranked([cmd], "caffeine").count == 1)
        check("aliases: the title still finds it", PaletteModel.ranked([cmd], String(cmd.title.prefix(4))).count == 1)
        PaletteAliases.set("   ", for: cmd.key)
        check("aliases: a blank alias removes it", Preferences.paletteAliases.value[cmd.key] == nil && PaletteModel.ranked([cmd], "caffeine").isEmpty)

        let request = UnitConverter.parse("10 km in mi")
        check("units: km to mi parses", request?.value == 10 && request?.from.name == "km" && request?.to.name == "mi")
        check("units: 10 km is 6.21371 mi", UnitConverter.answer("10 km in mi") == "6.21371 mi", UnitConverter.answer("10 km in mi") ?? "nil")
        check("units: to works like in", UnitConverter.answer("5 kg to lb") == "11.0231 lb", UnitConverter.answer("5 kg to lb") ?? "nil")
        check("units: temperatures go through kelvin", UnitConverter.answer("100 C to F") == "212 °F" && UnitConverter.answer("0 C in K") == "273.15 K", "\(UnitConverter.answer("100 C to F") ?? "nil")")
        check("units: a unit named in is inches", UnitConverter.answer("2 in in cm") == "5.08 cm", UnitConverter.answer("2 in in cm") ?? "nil")
        check("units: a decimal comma is accepted", UnitConverter.answer("10,5 km in m") == "10500 m", UnitConverter.answer("10,5 km in m") ?? "nil")
        check("units: currencies are not converted", UnitConverter.answer("100 usd in eur") == nil)
        check("units: different kinds do not convert", UnitConverter.answer("10 km in kg") == nil)
        check("units: an incomplete request is not one", UnitConverter.answer("10 km") == nil && UnitConverter.answer("5 + 3 in mi") == nil)

        check("shortcuts: the copy stack row shows its shortcut", PaletteModel.label(.pasteNext) == "⌃⌥V", PaletteModel.label(.pasteNext) ?? "nil")
        check("shortcuts: the first tab shows ⌘1", PaletteModel().commands.contains { $0.shortcut == "⌘1" })
    }
}
