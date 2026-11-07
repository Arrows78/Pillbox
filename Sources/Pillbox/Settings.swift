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
    @State private var copied = false

    var body: some View {
        Form {
            PermissionsSection()
            Section("General") {
                Toggle("Open when hovering the notch", isOn: $hoverOpen)
                if hoverOpen { Slider(value: $hoverDelay, in: 0.05...0.6) { Text("Hover delay") } }
                Toggle("Hide from screenshots and screen sharing", isOn: $hideFromCapture)
                Toggle("Hide the notch (black menu bar)", isOn: $hideNotch)
                Picker("Palette search engine", selection: $searchEngine) { ForEach(WebSearch.engines) { Text(verbatim: $0.name).tag($0.key) } }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                if NotchModel.shared.geometry.screen?.safeAreaInsets.top == 0 {
                    Slider(value: $pillWidth, in: 120...260) { Text("Pill width") }
                }
            }
            Section("Alerts") {
                Toggle("Caps Lock island", isOn: $capsHUD)
                Toggle("Download finished island", isOn: $downloadAlerts)
                Toggle("Microphone and camera indicator", isOn: $privacyIndicator)
                Toggle("Volume island", isOn: $volumeHUD)
                Toggle("Stage new screenshots on the shelf", isOn: $screenshotShelf)
                Toggle("Drive connected island with Eject", isOn: $driveEject)
                Toggle("Show keystrokes (for presentations)", isOn: $keystrokeHUD)
                if keystrokeHUD { Toggle("Shortcuts only, never plain typing", isOn: $shortcutsOnly) }
                Stepper("Charged island at \(fullCharge)%", value: $fullCharge, in: 80...100, step: 5)
            }
            Section("Island") {
                Toggle("Show a mini player when hovering during playback", isOn: $peekOnHover)
                Toggle("Double-press Control to open the notch", isOn: $doubleTapOpen)
                Toggle("Snap zones when dragging a window to the notch", isOn: $snapZones)
                Picker("Volume and brightness style", selection: $hudStyle) { Text("Bar").tag("notch"); Text("Circle").tag("circle") }
                Picker("Timer mascot", selection: $mascot) { ForEach(Mascot.allCases) { m in Text(verbatim: (m.emoji ?? "") + " " + m.title).tag(m.rawValue) } }
                HStack {
                    Text(verbatim: lottiePath.isEmpty ? L("Idle animation: none") : (lottiePath as NSString).lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Choose Lottie file…") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.json]
                        if p.runModal() == .OK, let u = p.url { lottiePath = u.path }
                    }.controlSize(.small)
                    if !lottiePath.isEmpty { Button("Remove") { lottiePath = "" }.controlSize(.small) }
                }
            }
            Section("Menu bar and desktop") {
                Toggle("Hide menu bar icons (⌘-drag them left of the divider)", isOn: $hideMenuBarIcons)
                Toggle("Next calendar event in the menu bar", isOn: $menuBarCalendar)
                ForEach(MenuBarDetach.detachable) { tab in DetachToggle(tab: tab) }
                Toggle("Desktop widgets (clock, world clock, weather, music)", isOn: $desktopWidgets)
                Toggle("Hyper key: Caps Lock becomes ⌃⌥⇧⌘", isOn: $hyperKey)
                if hyperKey { Toggle("A quick press sends Escape", isOn: $hyperEscape) }
            }
            Section("More alerts") {
                Toggle("Brightness island", isOn: $brightnessHUD)
                Toggle("Focus mode island", isOn: $focusIsland)
                Toggle("Call in progress island", isOn: $callIsland)
                Toggle("Live audio spectrum (asks for audio capture)", isOn: $liveSpectrum)
            }
            Section("Ask about screen") {
                SecureField("Anthropic API key", text: $apiKey).onSubmit { Keychain.set(apiKey, AskModel.keyService); keySaved = !apiKey.isEmpty; apiKey = "" }
                HStack {
                    Text(keySaved ? "A key is saved in your Keychain" : "No key saved").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save key") { Keychain.set(apiKey, AskModel.keyService); keySaved = !apiKey.isEmpty; apiKey = "" }.controlSize(.small).disabled(apiKey.isEmpty)
                    if keySaved { Button("Remove key") { Keychain.delete(AskModel.keyService); keySaved = false }.controlSize(.small) }
                }
            }
            Section("Developer API") {
                Text(verbatim: "127.0.0.1:\(DevAPI.defaultPort)").font(.caption).foregroundStyle(.secondary)
                Toggle("Enable local API", isOn: $devAPI).onChange(of: devAPI) { _ in DevAPI.shared.apply() }
                if devAPI {
                    Button("Copy Claude Code approval hook") {
                        let path = Bundle.main.path(forResource: "claude-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-hook.sh"
                        let cfg = "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash|Write|Edit\",\"hooks\":[{\"type\":\"command\",\"command\":\"\(path)\",\"timeout\":130}]}]}}"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cfg, forType: .string)
                    }
                    Button("Copy zsh hook for long-running commands") {
                        let hook = """
                        # Pillbox: show an island when a command runs longer than 15 s
                        autoload -Uz add-zsh-hook
                        _pillbox_pre() { _pb_cmd="$1"; _pb_t=$SECONDS }
                        _pillbox_post() { local s=$? d=$((SECONDS-${_pb_t:-$SECONDS})); [ -n "$_pb_cmd" ] && [ $d -ge 15 ] && curl -s -m 2 -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H "Authorization: Bearer $(defaults read dev.labs.pillbox devAPIToken)" -d "{\\"title\\":\\"Command finished (${d}s)\\",\\"message\\":\\"${_pb_cmd:0:80}\\",\\"symbol\\":\\"terminal.fill\\",\\"duration\\":5}" >/dev/null 2>&1 &!; _pb_cmd= }
                        add-zsh-hook preexec _pillbox_pre; add-zsh-hook precmd _pillbox_post
                        """
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hook, forType: .string)
                    }
                    Button(LocalizedStringKey(copied ? "Copied" : "Copy example request")) {
                        let cmd = "curl -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H 'Authorization: Bearer \(DevAPI.token)' -d '{\"title\":\"Build done\",\"symbol\":\"hammer.fill\"}'"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cmd, forType: .string); copied = true
                    }
                }
            }
            Section("Shortcuts") {
                Text("⌃⌥K  command palette    ⌃⌥N  toggle notch").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: 480, height: 640)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Pillbox Settings"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
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
        Toggle(isOn: $on) { Text("Show \(tab.title) in the menu bar") }
            .onChange(of: on) { v in
                var set = MenuBarDetach.wanted
                if v { set.insert(tab) } else { set.remove(tab) }
                UserDefaults.standard.set(set.map(\.rawValue).sorted(), forKey: "detachedTabs")
            }
    }
}
