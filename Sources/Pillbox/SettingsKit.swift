import SwiftUI

/// The settings window's own look: a sidebar of tinted panes and, in each page, titled cards of explained rows.
/// It follows the theme chosen in General (system, light or dark); the island itself always stays dark.
enum SettingsStyle {
    /// Window background that follows the appearance of the window.
    static let window = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.106, green: 0.106, blue: 0.118, alpha: 1) : NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    }
    static let sidebar = NSColor(name: nil) { appearance in
        NSColor.black.withAlphaComponent(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.18 : 0.04)
    }
    static let accent = Color(red: 0.357, green: 0.549, blue: 1)
    static let dim = Color.primary.opacity(0.45)

    /// The window's appearance for the saved theme: nil follows macOS.
    static func appearance(for theme: String?) -> NSAppearance? {
        switch theme {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, island, tabs, alerts, audio, windows, integrations, shortcuts, permissions, about
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .island: "Island"
        case .tabs: "Tabs and menu bar"
        case .alerts: "Alerts"
        case .audio: "Audio and sounds"
        case .windows: "Windows and keyboard"
        case .integrations: "Integrations"
        case .shortcuts: "Shortcuts"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .island: "capsule.fill"
        case .tabs: "menubar.rectangle"
        case .alerts: "bell.badge.fill"
        case .audio: "speaker.wave.2.fill"
        case .windows: "macwindow"
        case .integrations: "puzzlepiece.extension.fill"
        case .shortcuts: "keyboard.fill"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(red: 0.557, green: 0.557, blue: 0.576)
        case .island: Color(red: 0.357, green: 0.549, blue: 1)
        case .tabs: Color(red: 0.608, green: 0.42, blue: 1)
        case .alerts: Color(red: 1, green: 0.353, blue: 0.322)
        case .audio: Color(red: 0.941, green: 0.373, blue: 0.459)
        case .windows: Color(red: 1, green: 0.624, blue: 0.04)
        case .integrations: Color(red: 0.745, green: 0.353, blue: 0.949)
        case .shortcuts: Color(red: 0.173, green: 0.694, blue: 0.737)
        case .permissions: Color(red: 0.898, green: 0.282, blue: 0.302)
        case .about: Color(red: 0.357, green: 0.549, blue: 1)
        }
    }

    /// What the search matches: the pane's title, and the card and row titles it shows.
    var keywords: [String] {
        let names: [String]
        switch self {
        case .general: names = ["General", "Startup", "Launch at login", "Show in the menu bar", "Appearance", "Theme", "Command palette", "Search engine", "Backup", "Export settings…", "Import settings…", "Restore defaults…"]
        case .island: names = ["Island", "Notch", "Open when hovering the notch", "Hover delay", "Hide from screenshots and screen sharing", "Hide everywhere", "Hide the notch (black menu bar)", "Pill width", "Display", "Panel size", "Hide the island in full screen", "Hide the island while the screen is mirrored", "Close the island after", "Haptic feedback when the island opens", "Clock and battery on the resting pill", "Hide the pointer when it rests", "Show a mini player when hovering during playback", "Shake a dragged file to open the shelf", "Island appearance", "Island theme", "Volume and brightness style", "Timer mascot", "Idle animation", "Pill gestures", "Double-click the pill", "Triple-click the pill"]
        case .tabs: names = ["Tabs and menu bar", "Tabs", "Clipboard", "Menu bar", "Hide menu bar icons", "Next calendar event in the menu bar"]
        case .alerts: names = ["Alerts", "System", "Caps Lock island", "Volume island", "Brightness island", "Extra brightness on XDR screens", "Charged island", "Fast drain island", "Bluetooth audio island", "Drive connected island with Eject", "Download finished island", "Microphone and camera indicator", "Activity", "Focus mode island", "Call in progress island", "Build island", "Show new notifications as islands", "Verification codes with a Copy button", "Homebrew updates island", "Stage new screenshots on the shelf", "Warn when an AI limit reaches", "GitHub Copilot quota in AI usage", "Break reminder", "Eye breaks (20-20-20)", "Presentations", "Show keystrokes", "Shortcuts only, never plain typing", "Activity counter", "Count clicks, keystrokes and mouse distance", "Reset the counts"]
        case .audio: names = ["Audio and sounds", "Live audio spectrum", "Equalizer", "System equalizer", "Sounds", "Typing sounds", "Typing volume", "Ambient sound during focus", "Ambient volume"]
        case .windows: names = ["Windows and keyboard", "Swipe the resting pill to change desktop", "Move and resize windows with the mouse", "Snap zones when dragging a window to the notch", "Double-press Control to open the notch", "Copy stack", "Desktop and keyboard", "Desktop widgets", "Hyper key", "A quick press sends Escape"]
        case .integrations: names = ["Integrations", "Ask about screen", "Anthropic API key", "Developer API", "Enable local API", "Token", "Address"]
        case .shortcuts: names = ["Shortcuts", "Anywhere", "Open the notch", "While the island is open", "Switch tab", "While cleaning", "Unlock the keyboard"]
        case .permissions: names = ["Permissions"]
        case .about: names = ["About", "Version", "Updates", "Diagnostics", "Privacy", "Report a problem"]
        }
        return names.map { localized($0) }
    }

    /// The panes that match a search. An empty search matches every pane.
    static func matching(_ query: String) -> [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allCases }
        return allCases.filter { pane in pane.keywords.contains { $0.lowercased().contains(q) } }
    }
}

/// A titled, rounded group of rows. Each row draws the hairline above itself, so rows can come and go.
struct SettingsCard<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(SettingsStyle.dim).textCase(.uppercase).padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
        }
    }
}

/// One setting: a title, an optional explanation and the control on the right.
struct SettingsRow<Control: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.92))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(SettingsStyle.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 12) }
    }
}

struct SettingsToggle: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    /// The permission the feature needs. While it is missing, a warning sits under the switch, so the gap is seen here
    /// rather than discovered later through a silent feature.
    var needs: PermissionKind?

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>, needs: PermissionKind? = nil) {
        self.title = title; self.subtitle = subtitle; self._isOn = isOn; self.needs = needs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: title, subtitle: subtitle) {
                Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(SettingsStyle.accent)
            }
            if let needs, PermissionsCenter.shared.state(of: needs) != .granted {
                Label(localized("Needs %@ permission", needs.title), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }
}

/// A footnote under a card.
struct SettingsNote: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11)).foregroundStyle(SettingsStyle.dim).fixedSize(horizontal: false, vertical: true) }
}

/// A scrolling page with its tinted icon and title.
struct SettingsPage<Content: View>: View {
    var pane: SettingsPane
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: pane.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(pane.tint.gradient))
                    Text(pane.title).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
                }
                content
            }
            .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The sidebar: a search field, then one tinted tile and a name per pane that matches it.
struct SettingsSidebar: View {
    @Binding var pane: SettingsPane
    @Binding var query: String

    private var panes: [SettingsPane] { SettingsPane.matching(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(localized("Search settings"), text: $query)
                .textFieldStyle(.roundedBorder).controlSize(.small)
                .padding(.horizontal, 4).padding(.bottom, 8)
            ForEach(panes) { p in
                Button { pane = p } label: {
                    HStack(spacing: 9) {
                        Image(systemName: p.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 6).fill(p.tint.gradient))
                        Text(p.title).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(pane == p ? 1 : 0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(pane == p ? 0.12 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pane == p ? .isSelected : [])
                if p == .windows { Spacer().frame(height: 8) }
            }
            if panes.isEmpty {
                Text(localized("No matching settings")).font(.system(size: 12)).foregroundStyle(SettingsStyle.dim).padding(.horizontal, 8)
            }
            Spacer()
            SettingsSidebarFooter()
        }
        .padding(.horizontal, 10).padding(.top, 38)
        .frame(width: 190)
        .background(Color(nsColor: SettingsStyle.sidebar))
        .onChange(of: query) { _, _ in
            if let first = panes.first, !panes.contains(pane) { pane = first }
        }
    }
}

/// The app's icon, name and version at the foot of the sidebar.
struct SettingsSidebarFooter: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.primary.opacity(0.08)).padding(.horizontal, 2).padding(.bottom, 10)
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Pillbox").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.9))
                    Text(verbatim: localized("Version %@", version)).font(.system(size: 11)).foregroundStyle(SettingsStyle.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.bottom, 12)
        }
    }
}
