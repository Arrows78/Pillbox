import AppKit
import SwiftUI
import ServiceManagement

/// The Tabs and menu bar pane: which tabs the island shows, clipboard import and the menu bar items.
struct SettingsTabsPane: View {
    @AppStorage(Preferences.hideMenuBarIcons.key) private var hideMenuBarIcons = Preferences.hideMenuBarIcons.defaultValue
    @AppStorage(Preferences.menuBarAutoHide.key) private var menuBarAutoHide = Preferences.menuBarAutoHide.defaultValue
    @AppStorage(Preferences.menuBarCalendar.key) private var menuBarCalendar = Preferences.menuBarCalendar.defaultValue
    @AppStorage(Preferences.menuBarCalendarHours.key) private var menuBarCalendarHours = Preferences.menuBarCalendarHours.defaultValue
    @AppStorage(Preferences.shelfKeepDays.key) private var shelfKeepDays = Preferences.shelfKeepDays.defaultValue
    @AppStorage(Preferences.clipboardSecretMinutes.key) private var clipboardSecretMinutes = Preferences.clipboardSecretMinutes.defaultValue

    var body: some View {
        SettingsPage(pane: .tabs) {
            SettingsCard(title: "Tabs") {
                TabsPicker()
            }
            HomeLayoutSettings()
            SettingsCard(title: "Shelf") {
                SettingsRow(title: "Clear entries after", subtitle: "Older entries leave the shelf. The files themselves stay where they are.") {
                    Picker("", selection: $shelfKeepDays) {
                        Text("Never").tag(0); Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30)
                    }.labelsHidden().frame(width: 170)
                }
            }
            SettingsCard(title: "Clipboard") {
                ForEach(ClipboardImport.Source.allCases) { s in
                    SettingsRow(title: LocalizedStringKey(localized("Import history from %@", s.name)), subtitle: s.installed ? "Text items only. Their files are not changed." : "Not found on this Mac.") {
                        Button("Import") { ClipboardImport.run(s) }.controlSize(.small).disabled(!s.installed)
                    }
                }
                ClipboardExclusionRows()
                SettingsRow(title: "Remove secrets after", subtitle: "Secrets are API keys, tokens and card numbers. Pinned items stay.") {
                    Picker("", selection: $clipboardSecretMinutes) {
                        Text("Never").tag(0); Text(verbatim: "1 min").tag(1); Text(verbatim: "5 min").tag(5); Text(verbatim: "30 min").tag(30)
                    }.labelsHidden().frame(width: 170)
                }
            }
            SettingsCard(title: "Menu bar") {
                SettingsToggle("Hide menu bar icons", "Adds a divider: ⌘-drag icons to its left, then click the chevron to hide them.", isOn: $hideMenuBarIcons)
                if hideMenuBarIcons {
                    SettingsRow(title: "Show the hidden icons for", subtitle: "After a click on the chevron, they hide again by themselves.") {
                        Picker("", selection: $menuBarAutoHide) {
                            Text("Until I hide them").tag(0); Text(verbatim: "5 s").tag(5); Text(verbatim: "10 s").tag(10); Text(verbatim: "30 s").tag(30)
                        }.labelsHidden().frame(width: 170)
                    }
                }
                SettingsToggle("Next calendar event in the menu bar", "Needs Calendars access. A click on it lists today's events.", isOn: $menuBarCalendar)
                if menuBarCalendar {
                    SettingsRow(title: "Show it only when it is near", subtitle: "Further away, the menu bar shows nothing for it.") {
                        Picker("", selection: $menuBarCalendarHours) {
                            Text("Always").tag(0); Text(verbatim: "1 h").tag(1); Text(verbatim: "3 h").tag(3); Text(verbatim: "6 h").tag(6)
                        }.labelsHidden().frame(width: 170)
                    }
                }
                ForEach(MenuBarDetach.detachable) { tab in DetachToggle(tab: tab) }
            }
        }
    }
}

/// The apps whose copies are not recorded: one row per app with its name, and a button to add the app the user was in.
struct ClipboardExclusionRows: View {
    @State private var ids = ClipboardExclusions.ids

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Never record copies from", subtitle: ids.isEmpty ? "No app yet" : "Copies made while one of these apps is in front are not kept. Adds the app you used last, before Settings.") {
                Button("Add frontmost app") { ClipboardExclusions.addFrontmost(); ids = ClipboardExclusions.ids }.controlSize(.small)
            }
            ForEach(ids, id: \.self) { id in
                SettingsRow(title: LocalizedStringKey(BlockedAppsStore.name(id))) {
                    Button("Remove") { ClipboardExclusions.set(ClipboardExclusions.removing(id, from: ids)); ids = ClipboardExclusions.ids }.controlSize(.small)
                }
            }
        }
    }
}
