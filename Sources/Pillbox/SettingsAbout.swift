import AppKit
import SwiftUI
import ServiceManagement

/// The About pane: version, updates, diagnostics and the privacy statement.
struct SettingsAboutPane: View {
    @AppStorage(Preferences.autoUpdate.key) private var autoUpdate = Preferences.autoUpdate.defaultValue
    @AppStorage(Preferences.betaUpdates.key) private var betaUpdates = Preferences.betaUpdates.defaultValue

    var body: some View {
        SettingsPage(pane: .about) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Pillbox").font(.system(size: 22, weight: .bold))
                    Text(verbatim: localized("Version %@", Diagnostics.version)).font(.system(size: 12)).foregroundStyle(SettingsStyle.dim)
                    Text("A notch island for macOS: music, timers, clipboard, files and system alerts.").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            SettingsCard {
                SettingsRow(title: "Source code and releases") {
                    HStack {
                        Button("GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/Arrows78/Pillbox")!) }
                        Button("Releases") { NSWorkspace.shared.open(URL(string: "https://github.com/Arrows78/Pillbox/releases")!) }
                    }.controlSize(.small)
                }
                SettingsRow(title: "Updates", subtitle: "Asks GitHub for the latest release. The update installs in place and relaunches Pillbox.") {
                    Button("Check for updates…") { UpdateCheck.run() }.controlSize(.small)
                }
                SettingsToggle("Check for updates automatically", "Once a day. Only the version number is asked for; nothing about you is sent.", isOn: $autoUpdate)
                SettingsToggle("Include beta versions", "Also offers pre-releases, which may be less stable.", isOn: $betaUpdates)
                SettingsRow(title: "Diagnostics", subtitle: "Copies the version, macOS version and permissions, to paste into a bug report. It contains no personal data.") {
                    CopyButton(text: { Diagnostics.text }, title: "Copy diagnostics")
                }
                SettingsRow(title: "Recent logs", subtitle: "The last hour of Pillbox's log, for a bug report. Nothing leaves the Mac.") {
                    CopyButton(text: { Log.recentText() }, title: "Copy recent logs")
                }
                SettingsRow(title: "Report a problem", subtitle: "Opens a prefilled GitHub issue. Review it before sending.") {
                    Button("Report…") { ProblemReport.open() }.controlSize(.small)
                }
            }
            SettingsCard(title: "Privacy") {
                Text("Pillbox has no account and no analytics. It only uses the network when you use a feature: synced lyrics (LRCLIB), weather (Open-Meteo), stock quotes (Yahoo Finance), Spotify album art, Ask about screen (the recognised text only, to Anthropic, with your own key) and Check for updates (GitHub). Everything else stays on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.7)).fixedSize(horizontal: false, vertical: true).padding(12)
            }
        }
    }
}
