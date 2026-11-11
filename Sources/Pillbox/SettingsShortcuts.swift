import AppKit
import SwiftUI
import ServiceManagement

/// The Shortcuts pane: the shortcuts that are fixed and the ones that can be turned on.
struct SettingsShortcutsPane: View {
    @AppStorage(Preferences.doubleTapOpen.key) private var doubleTapOpen = Preferences.doubleTapOpen.defaultValue
    @AppStorage(Preferences.copyStack.key) private var copyStack = Preferences.copyStack.defaultValue
    @AppStorage(Preferences.dictationShortcut.key) private var dictationShortcut = Preferences.dictationShortcut.defaultValue

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
            SettingsNote("These shortcuts are fixed.")
        }
    }
}
