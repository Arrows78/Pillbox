import AppKit
import SwiftUI
import ServiceManagement

/// The Shortcuts pane: the shortcuts that are fixed and the ones that can be turned on.
struct SettingsShortcutsPane: View {
    @AppStorage(Preferences.doubleTapOpen.key) private var doubleTapOpen = Preferences.doubleTapOpen.defaultValue
    @AppStorage(Preferences.copyStack.key) private var copyStack = Preferences.copyStack.defaultValue
    @AppStorage(Preferences.dictationShortcut.key) private var dictationShortcut = Preferences.dictationShortcut.defaultValue
    /// The palette commands that take an alias, and the aliases typed so far (read when the pane appears).
    @State private var commands: [PaletteCommand] = []
    @State private var aliases: [String: String] = [:]

    var body: some View {
        SettingsPage(pane: .shortcuts) {
            SettingsCard(title: "Anywhere") {
                ForEach(GlobalShortcut.allCases, id: \.self) { s in
                    if s == .dictate {
                        SettingsRow(title: LocalizedStringKey(s.title), subtitle: "Speak, then press it again or Escape: the text is pasted and copied. Needs the microphone.") {
                            HStack(spacing: 10) {
                                Keycaps(s.keycaps).opacity(dictationShortcut ? 1 : 0.4)
                                Toggle("", isOn: $dictationShortcut).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(SettingsStyle.accent)
                            }
                        }
                    } else {
                        let note: String? = HotKey.unavailable.contains(s.rawValue) ? localized("Another app already uses this shortcut.")
                            : (s == .pasteNext && !copyStack ? "Turn on Copy stack in Island first." : nil)
                        SettingsRow(title: LocalizedStringKey(s.title), subtitle: note.map { LocalizedStringKey($0) }) { Keycaps(s.keycaps) }
                    }
                }
                if doubleTapOpen { SettingsRow(title: "Open the notch", subtitle: "Press Control twice quickly.") { Keycaps("⌃⌃") } }
            }
            SettingsCard(title: "While the island is open") {
                SettingsRow(title: "Switch tab", subtitle: "Or swipe left and right with two fingers. The numbers follow the tabs shown in the bar.") { Keycaps("⌘1–\(min(Tab.visible.count, 9))") }
            }
            SettingsCard(title: "While cleaning") {
                SettingsRow(title: "Unlock the keyboard") { Keycaps("⌘⎋") }
            }
            SettingsCard(title: "Command aliases") {
                ForEach(commands, id: \.key) { c in
                    SettingsRow(title: LocalizedStringKey(localized(c.key))) {
                        TextField("Alias", text: aliasBinding(c.key))
                            .textFieldStyle(.roundedBorder).frame(width: 150)
                    }
                }
            }
            SettingsNote("These shortcuts are fixed.")
        }
        .onAppear {
            aliases = UserDefaults.standard.dictionary(forKey: Preferences.paletteAliases.key) as? [String: String] ?? [:]
            commands = PaletteModel().commands.filter { !$0.key.isEmpty }
        }
    }

    /// Reads and writes one command's alias; the palette reads the same storage the next time it opens.
    private func aliasBinding(_ key: String) -> Binding<String> {
        Binding(get: { aliases[key] ?? "" }, set: { text in
            PaletteAliases.set(text, for: key)
            aliases[key] = PaletteAliases.clean(text)
        })
    }
}
