import AppKit
import SwiftUI

/// The settings window: a sidebar with a search field, and the chosen pane. Each pane lives in its own file.
struct SettingsView: View {
    @State private var pane: SettingsPane
    @State private var query = ""

    init(pane: SettingsPane = .general) { _pane = State(initialValue: pane) }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(pane: $pane, query: $query)
            Divider().overlay(Color.primary.opacity(0.08))
            page.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 580)
        .background(Color(nsColor: SettingsStyle.window))
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindow.paneRequest)) { note in
            if let requested = note.object as? SettingsPane { pane = requested }
        }
    }

    @ViewBuilder private var page: some View {
        switch pane {
        case .general: SettingsGeneralPane()
        case .island: SettingsIslandPane()
        case .tabs: SettingsTabsPane()
        case .alerts: SettingsAlertsPane()
        case .audio: SettingsAudioPane()
        case .windows: SettingsWindowsPane()
        case .integrations: SettingsIntegrationsPane()
        case .shortcuts: SettingsShortcutsPane()
        case .permissions: SettingsPage(pane: .permissions) { PermissionsCard() }
        case .about: SettingsAboutPane()
        }
    }
}
