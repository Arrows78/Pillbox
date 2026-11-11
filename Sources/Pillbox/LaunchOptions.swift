import AppKit

/// The debug switches of the app. Each one opens a window, a menu or a tab at launch, for screenshots and checks.
/// They are read once at launch; a switch that is not in this list is ignored.
@MainActor
enum LaunchOptions {
    static func has(_ flag: String, in args: [String] = CommandLine.arguments) -> Bool { args.contains(flag) }

    /// The argument after `flag`, or nil when there is none.
    static func value(after flag: String, in args: [String] = CommandLine.arguments) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// Opens what the switches ask for. Most wait a second so the app has a screen to show them on.
    static func apply(menu: NSMenu?) {
        if has("--open-teleprompter") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Teleprompter.shared.show() } }
        if has("--open-player") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { FloatingPlayer.shared.show() } }
        if has("--open-lyrics") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { LyricsScreen.shared.show() } }
        // `--open-menu` pops the menu-bar menu up in the middle of the screen (the icon may be hidden).
        if has("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { menu?.popUp(positioning: nil, at: NSPoint(x: 400, y: 900), in: nil) }
        }
        // `--open-settings integrations` opens the settings window on a pane; without a pane, General.
        if has("--open-settings") {
            let pane = value(after: "--open-settings").flatMap(SettingsPane.init(rawValue:))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindow.show(pane: pane ?? .general) }
        }
        if has("--open-palette") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PaletteController.shared.show() } }
        // `--open-tab ai` opens the notch on a tab and keeps it open (used to screenshot each tab).
        if let raw = value(after: "--open-tab"), let tab = Tab(rawValue: raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotchModel.shared.pinnedOpen = true; NotchModel.shared.expand(tab) }
        }
    }
}
