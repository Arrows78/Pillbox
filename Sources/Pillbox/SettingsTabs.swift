import AppKit
import SwiftUI
import ServiceManagement

/// The Tabs and menu bar pane: which tabs the island shows, clipboard import and the menu bar items.
struct SettingsTabsPane: View {
    @AppStorage(Preferences.hideMenuBarIcons.key) private var hideMenuBarIcons = Preferences.hideMenuBarIcons.defaultValue
    @AppStorage(Preferences.menuBarCalendar.key) private var menuBarCalendar = Preferences.menuBarCalendar.defaultValue

    var body: some View {
        SettingsPage(pane: .tabs) {
            SettingsCard(title: "Tabs") {
                TabsPicker()
            }
            HomeLayoutSettings()
            SettingsCard(title: "Clipboard") {
                ForEach(ClipboardImport.Source.allCases) { s in
                    SettingsRow(title: LocalizedStringKey(localized("Import history from %@", s.name)), subtitle: s.installed ? "Text items only. Their files are not changed." : "Not found on this Mac.") {
                        Button("Import") { ClipboardImport.run(s) }.controlSize(.small).disabled(!s.installed)
                    }
                }
            }
            SettingsCard(title: "Menu bar") {
                SettingsToggle("Hide menu bar icons", "Adds a divider: ⌘-drag icons to its left, then click the chevron to hide them.", isOn: $hideMenuBarIcons)
                SettingsToggle("Next calendar event in the menu bar", "Needs Calendars access.", isOn: $menuBarCalendar)
                ForEach(MenuBarDetach.detachable) { tab in DetachToggle(tab: tab) }
            }
        }
    }
}
