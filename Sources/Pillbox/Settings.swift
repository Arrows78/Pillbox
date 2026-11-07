import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("hoverOpen") private var hoverOpen = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.12
    @AppStorage("capsHUD") private var capsHUD = true
    @AppStorage("downloadAlerts") private var downloadAlerts = true
    @AppStorage("privacyIndicator") private var privacyIndicator = true
    @AppStorage("volumeHUD") private var volumeHUD = true
    @AppStorage("keystrokeHUD") private var keystrokeHUD = false
    @AppStorage("hideFromCapture") private var hideFromCapture = false
    @AppStorage("hideNotch") private var hideNotch = false
    @AppStorage("searchEngine") private var searchEngine = "google"
    @AppStorage("hyperKey") private var hyperKey = false
    @AppStorage("hyperEscape") private var hyperEscape = true
    @AppStorage("hideMenuBarIcons") private var hideMenuBarIcons = false
    @AppStorage("menuBarCalendar") private var menuBarCalendar = false
    @AppStorage("liveSpectrum") private var liveSpectrum = false
    @AppStorage("doubleTapOpen") private var doubleTapOpen = false
    @AppStorage("snapZones") private var snapZones = false
    @AppStorage("peekOnHover") private var peekOnHover = false
    @AppStorage("desktopWidgets") private var desktopWidgets = false
    @AppStorage("brightnessHUD") private var brightnessHUD = true
    @AppStorage("focusIsland") private var focusIsland = true
    @AppStorage("callIsland") private var callIsland = true
    @AppStorage("hudStyle") private var hudStyle = "notch"
    @AppStorage("usageAlert") private var usageAlert = 0
    @AppStorage("panelScale") private var panelScale = 1.0
    @AppStorage("copyStack") private var copyStack = false
    @AppStorage("islandTheme") private var islandTheme = "black"
    @AppStorage("doubleClickAction") private var doubleClickAction = "none"
    @AppStorage("tripleClickAction") private var tripleClickAction = "none"
    @AppStorage("notificationIsland") private var notificationIsland = false
    @AppStorage("shakeToOpen") private var shakeToOpen = true
    @AppStorage("breakReminder") private var breakReminder = 0
    @AppStorage("buildIsland") private var buildIsland = true
    @AppStorage("hideInFullScreen") private var hideInFullScreen = false
    @AppStorage("targetDisplay") private var targetDisplay = ""
    @AppStorage("mascot") private var mascot = "none"
    @AppStorage("lottiePath") private var lottiePath = ""
    @State private var apiKey = ""
    @State private var keySaved = Keychain.get(AskModel.keyService) != nil
    @AppStorage("screenshotShelf") private var screenshotShelf = true
    @AppStorage("driveEject") private var driveEject = true
    @AppStorage("shortcutsOnly") private var shortcutsOnly = true
    @AppStorage("fullChargeLevel") private var fullCharge = 100
    @AppStorage("pillWidth") private var pillWidth = 170.0
    @AppStorage("devAPIEnabled") private var devAPI = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @State private var pane: SettingsPane

    init(pane: SettingsPane = .general) { _pane = State(initialValue: pane) }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(pane: $pane)
            Divider().overlay(Color.white.opacity(0.08))
            page.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 580)
        .background(Color(nsColor: SettingsStyle.window))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var page: some View {
        switch pane {
        case .general: general
        case .island: island
        case .alerts: alerts
        case .menuBar: menuBar
        case .quickActions: quickActions
        case .ask: ask
        case .developer: developer
        case .shortcuts: shortcuts
        case .permissions: permissions
        case .about: about
        }
    }

    private var general: some View {
        SettingsPage(pane: .general) {
            SettingsCard(title: "General") {
                SettingsToggle("Open when hovering the notch", isOn: $hoverOpen)
                if hoverOpen { SettingsRow(title: "Hover delay") { Slider(value: $hoverDelay, in: 0.05...0.6).frame(width: 180) } }
                SettingsToggle("Hide from screenshots and screen sharing", "Pillbox stays out of screenshots, recordings and screen sharing.", isOn: $hideFromCapture)
                SettingsToggle("Hide the notch (black menu bar)", "Paints the menu bar black so the notch disappears.", isOn: $hideNotch)
                SettingsRow(title: "Palette search engine") {
                    Picker("", selection: $searchEngine) { ForEach(WebSearch.engines) { Text(verbatim: $0.name).tag($0.key) } }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                if NotchModel.shared.geometry.screen?.safeAreaInsets.top == 0 {
                    SettingsRow(title: "Pill width") { Slider(value: $pillWidth, in: 120...260).frame(width: 180) }
                }
            }
        }
    }

    private var island: some View {
        SettingsPage(pane: .island) {
            SettingsCard(title: "Island") {
                SettingsToggle("Show a mini player when hovering during playback", isOn: $peekOnHover)
                SettingsToggle("Double-press Control to open the notch", isOn: $doubleTapOpen)
                SettingsToggle("Snap zones when dragging a window to the notch", isOn: $snapZones)
                SettingsRow(title: "Panel size") { Slider(value: $panelScale, in: 0.8...1.3).frame(width: 180) }
                SettingsToggle("Copy stack: copy several things, paste them in order with ⌃⌥V", isOn: $copyStack)
                SettingsToggle("Shake a dragged file to open the shelf", isOn: $shakeToOpen)
                SettingsToggle("Hide the island in full screen", isOn: $hideInFullScreen)
                SettingsRow(title: "Display") {
                    Picker("", selection: $targetDisplay) {
                        Text("Automatic").tag("")
                        ForEach(NSScreen.screens, id: \.localizedName) { Text(verbatim: $0.localizedName).tag($0.localizedName) }
                    }.labelsHidden().frame(width: 170)
                }
            }
            SettingsCard(title: "Appearance") {
                SettingsRow(title: "Island theme") {
                    Picker("", selection: $islandTheme) { ForEach(IslandTheme.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) } }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Volume and brightness style") {
                    Picker("", selection: $hudStyle) { Text("Bar").tag("notch"); Text("Edge bar").tag("edge"); Text("Circle").tag("circle") }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Timer mascot") {
                    Picker("", selection: $mascot) { ForEach(Mascot.allCases) { m in Text(verbatim: (m.emoji ?? "") + " " + m.title).tag(m.rawValue) } }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: lottiePath.isEmpty ? "Idle animation: none" : LocalizedStringKey((lottiePath as NSString).lastPathComponent)) {
                    HStack {
                        Button("Choose Lottie file…") {
                            let p = NSOpenPanel(); p.allowedContentTypes = [.json]
                            if p.runModal() == .OK, let u = p.url { lottiePath = u.path }
                        }
                        if !lottiePath.isEmpty { Button("Remove") { lottiePath = "" } }
                    }.controlSize(.small)
                }
            }
            SettingsCard(title: "Pill gestures") {
                SettingsRow(title: "Double-click the pill") {
                    Picker("", selection: $doubleClickAction) { ForEach(PillAction.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Triple-click the pill") {
                    Picker("", selection: $tripleClickAction) { ForEach(PillAction.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 170)
                }
            }
        }
    }

    private var alerts: some View {
        SettingsPage(pane: .alerts) {
            SettingsCard(title: "Alerts") {
                SettingsToggle("Caps Lock island", isOn: $capsHUD)
                SettingsToggle("Download finished island", isOn: $downloadAlerts)
                SettingsToggle("Microphone and camera indicator", isOn: $privacyIndicator)
                SettingsToggle("Volume island", isOn: $volumeHUD)
                SettingsToggle("Stage new screenshots on the shelf", isOn: $screenshotShelf)
                SettingsToggle("Drive connected island with Eject", isOn: $driveEject)
                SettingsToggle("Show keystrokes (for presentations)", isOn: $keystrokeHUD)
                if keystrokeHUD { SettingsToggle("Shortcuts only, never plain typing", isOn: $shortcutsOnly) }
                SettingsRow(title: "Charged island at \(fullCharge)%") { Stepper("", value: $fullCharge, in: 80...100, step: 5).labelsHidden() }
            }
            SettingsCard(title: "More alerts") {
                SettingsToggle("Brightness island", isOn: $brightnessHUD)
                SettingsRow(title: "Warn when an AI limit reaches") {
                    Picker("", selection: $usageAlert) { Text("Never").tag(0); Text("70%").tag(70); Text("80%").tag(80); Text("90%").tag(90) }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Focus mode island", isOn: $focusIsland)
                SettingsToggle("Show new notifications as islands (Full Disk Access)", isOn: $notificationIsland)
                SettingsToggle("Call in progress island", isOn: $callIsland)
                SettingsToggle("Build island (Xcode and swift build)", isOn: $buildIsland)
                SettingsRow(title: "Break reminder") {
                    Picker("", selection: $breakReminder) {
                        Text("Off").tag(0); Text("Every 20 min").tag(20); Text("Every 30 min").tag(30); Text("Every 45 min").tag(45); Text("Every hour").tag(60)
                    }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Live audio spectrum (asks for audio capture)", isOn: $liveSpectrum)
            }
        }
    }

    private var menuBar: some View {
        SettingsPage(pane: .menuBar) {
            SettingsCard(title: "Menu bar and desktop") {
                SettingsToggle("Hide menu bar icons (⌘-drag them left of the divider)", isOn: $hideMenuBarIcons)
                SettingsToggle("Next calendar event in the menu bar", isOn: $menuBarCalendar)
                ForEach(MenuBarDetach.detachable) { tab in DetachToggle(tab: tab) }
                SettingsToggle("Desktop widgets (clock, world clock, weather, music)", isOn: $desktopWidgets)
                SettingsToggle("Hyper key: Caps Lock becomes ⌃⌥⇧⌘", isOn: $hyperKey)
                if hyperKey { SettingsToggle("A quick press sends Escape", isOn: $hyperEscape) }
            }
        }
    }

    private var quickActions: some View {
        SettingsPage(pane: .quickActions) {
            SettingsCard { VStack(alignment: .leading, spacing: 8) { QuickActionsEditor() }.padding(12) }
        }
    }

    private var ask: some View {
        SettingsPage(pane: .ask) {
            SettingsCard(title: "Ask about screen") {
                SettingsRow(title: "Anthropic API key", subtitle: keySaved ? "A key is saved in your Keychain" : "No key saved") {
                    HStack {
                        SecureField("", text: $apiKey).textFieldStyle(.roundedBorder).frame(width: 200)
                            .onSubmit { Keychain.set(apiKey, AskModel.keyService); keySaved = !apiKey.isEmpty; apiKey = "" }
                        Button("Save key") { Keychain.set(apiKey, AskModel.keyService); keySaved = !apiKey.isEmpty; apiKey = "" }.disabled(apiKey.isEmpty)
                        if keySaved { Button("Remove key") { Keychain.delete(AskModel.keyService); keySaved = false } }
                    }.controlSize(.small)
                }
            }
        }
    }

    private var developer: some View {
        SettingsPage(pane: .developer) {
            SettingsCard(title: "Developer API") {
                SettingsRow(title: "Enable local API", subtitle: LocalizedStringKey("127.0.0.1:\(DevAPI.defaultPort)")) {
                    Toggle("", isOn: $devAPI).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(SettingsStyle.accent)
                        .onChange(of: devAPI) { _ in DevAPI.shared.apply() }
                }
                if devAPI {
                    copyRow("Copy MCP configuration") {
                        MCPServer.configuration(executable: Bundle.main.executablePath ?? "/Applications/Pillbox.app/Contents/MacOS/Pillbox")
                    }
                    copyRow("Copy Claude Code turn-summary hook") {
                        let path = Bundle.main.path(forResource: "claude-stop-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-stop-hook.sh"
                        return "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"\(path)\",\"timeout\":10}]}]}}"
                    }
                    copyRow("Copy Claude Code approval hook") {
                        let path = Bundle.main.path(forResource: "claude-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-hook.sh"
                        return "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash|Write|Edit\",\"hooks\":[{\"type\":\"command\",\"command\":\"\(path)\",\"timeout\":130}]}]}}"
                    }
                    copyRow("Copy zsh hook for long-running commands") { Self.zshHook }
                    copyRow("Copy example request") {
                        "curl -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H 'Authorization: Bearer \(DevAPI.token)' -d '{\"title\":\"Build done\",\"symbol\":\"hammer.fill\"}'"
                    }
                }
            }
        }
    }

    /// A row whose button puts `text()` on the pasteboard and says so.
    private func copyRow(_ title: LocalizedStringKey, text: @escaping () -> String) -> some View {
        SettingsRow(title: title) { CopyButton(text: text) }
    }

    private static let zshHook = """
    # Pillbox: show an island when a command runs longer than 15 s
    autoload -Uz add-zsh-hook
    _pillbox_pre() { _pb_cmd="$1"; _pb_t=$SECONDS }
    _pillbox_post() { local s=$? d=$((SECONDS-${_pb_t:-$SECONDS})); [ -n "$_pb_cmd" ] && [ $d -ge 15 ] && curl -s -m 2 -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H "Authorization: Bearer $(defaults read dev.labs.pillbox devAPIToken)" -d "{\\"title\\":\\"Command finished (${d}s)\\",\\"message\\":\\"${_pb_cmd:0:80}\\",\\"symbol\\":\\"terminal.fill\\",\\"duration\\":5}" >/dev/null 2>&1 &!; _pb_cmd= }
    add-zsh-hook preexec _pillbox_pre; add-zsh-hook precmd _pillbox_post
    """

    private var shortcuts: some View {
        SettingsPage(pane: .shortcuts) {
            SettingsCard {
                SettingsRow(title: "Command palette") { Keycaps("⌃⌥K") }
                SettingsRow(title: "Toggle Notch") { Keycaps("⌃⌥N") }
                SettingsRow(title: "Paste next from the copy stack") { Keycaps("⌃⌥V") }
            }
        }
    }

    private var permissions: some View {
        SettingsPage(pane: .permissions) { PermissionsCard() }
    }

    private var about: some View {
        SettingsPage(pane: .about) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Pillbox").font(.system(size: 18, weight: .bold))
                    Text(verbatim: L("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).font(.system(size: 12)).foregroundStyle(SettingsStyle.dim)
                }
            }
            SettingsCard {
                SettingsRow(title: "Source code and releases") {
                    Button("Open on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/Arrows78/Pillbox")!) }.controlSize(.small)
                }
            }
        }
    }
}

/// "Copy" that turns into "Copied" for a moment.
struct CopyButton: View {
    let text: () -> String
    @State private var copied = false

    var body: some View {
        Button(LocalizedStringKey(copied ? "Copied" : "Copy")) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text(), forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }.controlSize(.small)
    }
}

/// A shortcut drawn as keycaps.
struct Keycaps: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(String(k)).font(.system(size: 12, weight: .medium, design: .rounded)).frame(minWidth: 22, minHeight: 22)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show(pane: SettingsPane = .general) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(pane: pane)))
            w.title = "Pillbox Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = SettingsStyle.window
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); window?.makeKeyAndOrderFront(nil)
    }
}

struct DetachToggle: View {
    let tab: Tab
    @State private var on: Bool
    init(tab: Tab) { self.tab = tab; _on = State(initialValue: MenuBarDetach.wanted.contains(tab)) }
    var body: some View {
        SettingsToggle("Show \(tab.title) in the menu bar", isOn: $on)
            .onChange(of: on) { v in
                var set = MenuBarDetach.wanted
                if v { set.insert(tab) } else { set.remove(tab) }
                UserDefaults.standard.set(set.map(\.rawValue).sorted(), forKey: "detachedTabs")
            }
    }
}
