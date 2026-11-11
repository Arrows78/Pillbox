import AppKit
import SwiftUI
import ServiceManagement

/// The General pane: startup, theme, the command palette's search engine, calendars and backups.
struct SettingsGeneralPane: View {
    @AppStorage(Preferences.searchEngine.key) private var searchEngine = Preferences.searchEngine.defaultValue
    @AppStorage(Preferences.appearance.key) private var appearance = Preferences.appearance.defaultValue
    @AppStorage(Preferences.showMenuBarIcon.key) private var showMenuBarIcon = Preferences.showMenuBarIcon.defaultValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private func setLaunchAtLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }   // the switch must not claim what macOS refused
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "Pillbox Settings.plist"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = SettingsBackup.data() else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
            NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: "Settings exported", tint: .green))
        } catch {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: "Could not export the settings", subtitle: error.localizedDescription, tint: .orange))
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            let alert = NSAlert()
            alert.messageText = localized("Could not read the backup file")
            alert.informativeText = error.localizedDescription
            alert.runModal(); return
        }
        guard let n = SettingsBackup.restore(data) else {
            let alert = NSAlert()
            alert.messageText = localized("This file is not a Pillbox backup")
            alert.runModal(); return
        }
        NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: "Settings imported", subtitle: localized("%d setting(s) applied", n), tint: .green))
    }

    private func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = localized("Restore default settings?")
        alert.informativeText = localized("Every preference goes back to its default. Your notes, clipboard history, shelf and quick actions are kept.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("Restore"))
        alert.addButton(withTitle: localized("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SettingsBackup.resetAll()
        NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: "Settings restored", tint: .green))
    }

    var body: some View {
        SettingsPage(pane: .general) {
            SettingsCard(title: "Startup") {
                SettingsToggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                SettingsToggle("Show in the menu bar", "When hidden, open Settings from the gear on the island or by launching Pillbox again.", isOn: $showMenuBarIcon)
            }
            SettingsCard(title: "Appearance") {
                SettingsRow(title: "Theme", subtitle: "Applies to this window. The island always stays dark.") {
                    Picker("", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.labelsHidden().frame(width: 140)
                }
            }
            SettingsCard(title: "Command palette") {
                SettingsRow(title: "Search engine", subtitle: "Used for text that is not a command. Start with a prefix such as yt or gh to pick another one.") {
                    Picker("", selection: $searchEngine) { ForEach(WebSearch.engines) { Text(verbatim: $0.name).tag($0.key) } }.labelsHidden().frame(width: 170)
                }
            }
            CalendarsSettings()
            SettingsCard(title: "Backup") {
                SettingsRow(title: "Export settings…", subtitle: "Saves your preferences to a file. Notes, clipboard history, the shelf and quick actions are not included.") {
                    Button("Export…") { exportSettings() }.controlSize(.small)
                }
                SettingsRow(title: "Import settings…", subtitle: "Applies a backup file. Settings it does not contain stay as they are.") {
                    Button("Import…") { importSettings() }.controlSize(.small)
                }
                SettingsRow(title: "Restore defaults…", subtitle: "Puts every preference back to its default. Your data and Launch at login are kept.") {
                    Button("Restore…", role: .destructive) { restoreDefaults() }.controlSize(.small)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: appearance) { _, _ in SettingsWindow.applyTheme() }
    }
}
