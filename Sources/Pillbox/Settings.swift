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
    @AppStorage("hideEverywhere") private var hideEverywhere = false
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
    @AppStorage(ExtraBrightness.key) private var extraBrightness = false
    @AppStorage(WindowDrag.key) private var windowDrag = false
    @AppStorage(EqualizerKeys.key) private var systemEQ = false
    @AppStorage(EqualizerKeys.bassKey) private var eqBass = 0.0
    @AppStorage(EqualizerKeys.midKey) private var eqMid = 0.0
    @AppStorage(EqualizerKeys.trebleKey) private var eqTreble = 0.0

    /// Applies the equalizer settings; the service exists only from macOS 14.2.
    private func refreshEqualizer() {
        if #available(macOS 14.2, *) { EqualizerService.shared.apply() }
    }

    /// One equalizer band: a slider from -12 to +12 dB that reapplies the equalizer as it moves.
    private func equalizerRow(_ title: LocalizedStringKey, _ gain: Binding<Double>) -> some View {
        SettingsRow(title: title) { Slider(value: gain, in: -12...12).frame(width: 180).onChange(of: gain.wrappedValue) { _, _ in refreshEqualizer() } }
    }

    /// The Display picker's choice by screen position. Two identical monitors share a name, so the position is what tells them apart;
    /// the name stays in `targetDisplay`, which the island reads.
    private var displaySelection: Binding<String> {
        Binding(get: {
            NSScreen.screens.firstIndex { $0.localizedName == targetDisplay }.map { String($0) } ?? ""
        }, set: { tag in
            if let i = Int(tag), NSScreen.screens.indices.contains(i) { targetDisplay = NSScreen.screens[i].localizedName } else { targetDisplay = "" }
        })
    }

    /// Stores the typed key. Save and Enter both call it; the field clears and the row says "saved" only when the Keychain accepted the key.
    private func saveKey() {
        guard !apiKey.isEmpty else { return }
        guard Keychain.set(apiKey, AskModel.keyService) else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not save the key in the Keychain"), tint: .orange))
            return
        }
        keySaved = true; apiKey = ""
    }
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
    @AppStorage("drainAlert") private var drainAlert = 0
    @AppStorage("bluetoothIsland") private var bluetoothIsland = false
    @AppStorage("pillWidth") private var pillWidth = 170.0
    @AppStorage("devAPIEnabled") private var devAPI = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("dictationShortcut") private var dictationShortcut = false
    @AppStorage("activityCounter") private var activityCounter = false
    @AppStorage(IdlePill.key) private var idleClock = false
    @AppStorage(Haptics.key) private var hapticIsland = false
    @AppStorage(IdleCollapse.key) private var idleCollapse = 0
    @AppStorage(PointerHider.key) private var hidePointer = 0
    @AppStorage(Mirroring.key) private var hideWhileMirroring = false
    @AppStorage(SpaceSwipe.key) private var swipeSpaces = false
    @AppStorage(EyeBreaks.key) private var eyeBreaks = false
    @AppStorage(NotificationFeed.codeIslandKey) private var codeIsland = true
    @AppStorage(Updater.autoKey) private var autoUpdate = false
    @AppStorage(Updater.betaKey) private var betaUpdates = false
    @AppStorage(BrewUpdates.key) private var brewUpdates = false
    @AppStorage(AIUsageService.copilotKey) private var copilotUsage = false
    @AppStorage(TypingSounds.profileKey) private var typingProfile = "off"
    @AppStorage(TypingSounds.volumeKey) private var typingVolume = 0.5
    @AppStorage(AmbientNoise.kindKey) private var ambientKind = "off"
    @AppStorage(AmbientNoise.volumeKey) private var ambientVolume = 0.3
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @State private var pane: SettingsPane

    init(pane: SettingsPane = .general) { _pane = State(initialValue: pane) }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(pane: $pane)
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
            SettingsCard(title: "Notch") {
                SettingsToggle("Open when hovering the notch", isOn: $hoverOpen)
                if hoverOpen { SettingsRow(title: "Hover delay") { Slider(value: $hoverDelay, in: 0.05...0.6).frame(width: 180) } }
                SettingsToggle("Hide from screenshots and screen sharing", "Pillbox stays out of screenshots, recordings and screen sharing.", isOn: $hideFromCapture)
                SettingsToggle("Hide everywhere", "Also hides the island on your own screen, not only from captures. Its shortcuts keep working; open Settings from the menu bar icon to turn it back on.", isOn: $hideEverywhere)
                SettingsToggle("Hide the notch (black menu bar)", "Paints the menu bar black so the notch disappears.", isOn: $hideNotch)
                if NotchModel.shared.geometry.screen?.safeAreaInsets.top == 0 {
                    SettingsRow(title: "Pill width", subtitle: "Width of the pill on a screen without a notch.") { Slider(value: $pillWidth, in: 120...260).frame(width: 180) }
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

    private var island: some View {
        SettingsPage(pane: .island) {
            SettingsCard(title: "Island") {
                SettingsRow(title: "Display", subtitle: "Which screen shows the island. Automatic uses the screen with the notch.") {
                    Picker("", selection: displaySelection) {
                        Text("Automatic").tag("")
                        ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in Text(verbatim: screen.localizedName).tag(String(index)) }
                    }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Panel size") { Slider(value: $panelScale, in: 0.8...1.3).frame(width: 180) }
                SettingsToggle("Hide the island in full screen", isOn: $hideInFullScreen)
                SettingsToggle("Hide the island while the screen is mirrored", "A projector or a TV copies the whole screen, so the island goes away outright.", isOn: $hideWhileMirroring)
                SettingsRow(title: "Close the island after", subtitle: "Without any input. Fields being edited and the Terminal keep it open.") {
                    Picker("", selection: $idleCollapse) { Text("Never").tag(0); Text("10 s").tag(10); Text("30 s").tag(30); Text("1 min").tag(60) }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Haptic feedback when the island opens", "A light tap of the trackpad.", isOn: $hapticIsland)
                SettingsToggle("Clock and battery on the resting pill", "Shown on the wings when nothing else is live.", isOn: $idleClock)
                SettingsToggle("Swipe the resting pill to change desktop", "Two fingers left or right on the pill. Needs Accessibility.", isOn: $swipeSpaces, needs: .accessibility)
                SettingsRow(title: "Hide the pointer when it rests", subtitle: "In every app, handy for films. Any movement brings it back.") {
                    Picker("", selection: $hidePointer) { Text("Never").tag(0); Text("5 s").tag(5); Text("10 s").tag(10); Text("30 s").tag(30) }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Show a mini player when hovering during playback", isOn: $peekOnHover)
                SettingsToggle("Shake a dragged file to open the shelf", isOn: $shakeToOpen)
                SettingsToggle("Move and resize windows with the mouse", "Hold ⌃⌥ and drag a window to move it; add ⇧ to resize it. Needs Accessibility.", isOn: $windowDrag, needs: .accessibility)
                SettingsToggle("Snap zones when dragging a window to the notch", "Needs Accessibility. Drop the window on a zone to tile it.", isOn: $snapZones, needs: .accessibility)
                SettingsToggle("Double-press Control to open the notch", "Needs Input Monitoring.", isOn: $doubleTapOpen, needs: .inputMonitoring)
                SettingsToggle("Copy stack", "Copy several things, then paste them one by one, in order, with the Paste next shortcut.", isOn: $copyStack)
            }
            SettingsCard(title: "Tabs") {
                TabsPicker()
            }
            SettingsCard(title: "Clipboard") {
                ForEach(ClipboardImport.Source.allCases) { s in
                    SettingsRow(title: LocalizedStringKey(localized("Import history from %@", s.name)), subtitle: s.installed ? "Text items only. Their files are not changed." : "Not found on this Mac.") {
                        Button("Import") { ClipboardImport.run(s) }.controlSize(.small).disabled(!s.installed)
                    }
                }
            }
            SettingsCard(title: "Island appearance") {
                SettingsRow(title: "Island theme", subtitle: "The collapsed pill always stays black to blend into the notch.") {
                    Picker("", selection: $islandTheme) { ForEach(IslandTheme.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) } }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Volume and brightness style") {
                    Picker("", selection: $hudStyle) { Text("Bar").tag("notch"); Text("Edge bar").tag("edge"); Text("Circle").tag("circle") }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Timer mascot") {
                    Picker("", selection: $mascot) { ForEach(Mascot.allCases) { m in Text(verbatim: (m.emoji ?? "") + " " + m.title).tag(m.rawValue) } }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Idle animation", subtitle: lottiePath.isEmpty ? LocalizedStringKey("None") : LocalizedStringKey((lottiePath as NSString).lastPathComponent)) {
                    HStack {
                        Button("Choose Lottie file…") {
                            let p = NSOpenPanel(); p.allowedContentTypes = [.json]
                            if p.runModal() == .OK, let u = p.url { lottiePath = u.path }
                        }
                        if !lottiePath.isEmpty { Button("Remove") { lottiePath = "" } }
                    }.controlSize(.small)
                }
                SettingsToggle("Live audio spectrum", "The equalizer follows the real sound. Asks for audio capture.", isOn: $liveSpectrum)
            }
            if #available(macOS 14.2, *) {
                SettingsCard(title: "Equalizer") {
                    SettingsToggle("System equalizer", "Shapes everything the Mac plays. Needs System Audio Recording. Off by default.", isOn: $systemEQ)
                        .onChange(of: systemEQ) { _, _ in refreshEqualizer() }
                    if systemEQ {
                        equalizerRow("Bass", $eqBass)
                        equalizerRow("Mid", $eqMid)
                        equalizerRow("Treble", $eqTreble)
                    }
                }
            }
            SettingsCard(title: "Sounds") {
                SettingsRow(title: "Typing sounds", subtitle: "A click on every key press, made on the Mac. Needs Input Monitoring. Which keys you press is never kept.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $typingProfile) { ForEach(TypingSounds.Profile.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 110)
                        Button("Try") { TypingSounds.shared.preview(TypingSounds.Profile(rawValue: typingProfile) ?? .soft) }.controlSize(.small).disabled(typingProfile == "off")
                    }
                }
                if typingProfile != "off" { SettingsRow(title: "Typing volume") { Slider(value: $typingVolume, in: 0.05...1).frame(width: 180) } }
                SettingsRow(title: "Ambient sound during focus", subtitle: "Plays while a Focus session runs and fades out when it ends. Also in the Timer tab and the palette.") {
                    Picker("", selection: $ambientKind) { ForEach(AmbientNoise.Kind.allCases) { Text(verbatim: $0.title).tag($0.rawValue) } }.labelsHidden().frame(width: 150)
                }
                if ambientKind != "off" {
                    SettingsRow(title: "Ambient volume") { Slider(value: $ambientVolume, in: 0.05...1).frame(width: 180).onChange(of: ambientVolume) { AmbientNoise.shared.setVolume(Float($0)) } }
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
            SettingsCard(title: "System") {
                SettingsToggle("Caps Lock island", isOn: $capsHUD)
                SettingsToggle("Volume island", isOn: $volumeHUD)
                SettingsToggle("Brightness island", isOn: $brightnessHUD)
                SettingsToggle("Extra brightness on XDR screens", "Lifts the built-in XDR screen slightly above standard white. Uses more power.", isOn: $extraBrightness)
                SettingsRow(title: "Charged island", subtitle: "Shows when the battery reaches this level while plugged in.") {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(fullCharge)%").monospacedDigit().foregroundStyle(SettingsStyle.dim)
                        Stepper("", value: $fullCharge, in: 80...100, step: 5).labelsHidden()
                    }
                }
                SettingsRow(title: "Fast drain island", subtitle: "On battery, when the level falls this fast.") {
                    Picker("", selection: $drainAlert) { Text("Off").tag(0); ForEach([3, 5, 8], id: \.self) { Text(verbatim: "−\($0)%/10 min").tag($0) } }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Bluetooth audio island", "AirPods and headphones connecting, with their battery. Asks for Bluetooth access.", isOn: $bluetoothIsland)
                    .onChange(of: bluetoothIsland) { _, _ in BluetoothIslands.shared.apply() }
                SettingsToggle("Drive connected island with Eject", isOn: $driveEject)
                SettingsToggle("Download finished island", "Also shows the size of a download while it runs.", isOn: $downloadAlerts)
                SettingsToggle("Microphone and camera indicator", "Shows when an app is using the microphone or the camera.", isOn: $privacyIndicator)
            }
            SettingsCard(title: "Activity") {
                SettingsToggle("Focus mode island", "Needs Full Disk Access.", isOn: $focusIsland, needs: .fullDisk)
                SettingsToggle("Call in progress island", "Shows the duration while a call app uses the microphone.", isOn: $callIsland)
                SettingsToggle("Build island", "Shows a stopwatch while Xcode or swift build runs.", isOn: $buildIsland)
                SettingsToggle("Show new notifications as islands", "Needs Full Disk Access.", isOn: $notificationIsland, needs: .fullDisk)
                SettingsToggle("Verification codes with a Copy button", "A code in a new notification becomes an island. Needs Full Disk Access.", isOn: $codeIsland, needs: .fullDisk)
                SettingsToggle("Homebrew updates island", "Once a day, the packages with a newer version, with Upgrade in the Terminal tab.", isOn: $brewUpdates)
                SettingsToggle("Stage new screenshots on the shelf", isOn: $screenshotShelf)
                SettingsRow(title: "Warn when an AI limit reaches", subtitle: "Codex and Copilot usage limits.") {
                    Picker("", selection: $usageAlert) { Text("Never").tag(0); Text("70%").tag(70); Text("80%").tag(80); Text("90%").tag(90) }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("GitHub Copilot quota in AI usage", "Asks GitHub through the gh command and its own login, every 2 minutes while on. Pillbox stores no token.", isOn: $copilotUsage)
                    .onChange(of: copilotUsage) { _, _ in AIUsageService.shared.refresh() }
                AIUsageOrderRows()
                SettingsRow(title: "Break reminder", subtitle: "Suggests a pause after this long at the keyboard.") {
                    Picker("", selection: $breakReminder) {
                        Text("Off").tag(0); Text("Every 20 min").tag(20); Text("Every 30 min").tag(30); Text("Every 45 min").tag(45); Text("Every hour").tag(60)
                    }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Eye breaks (20-20-20)", "Every 20 minutes at the keyboard, 20 seconds to look at something far away, counted down on the island.", isOn: $eyeBreaks)
            }
            AwarenessSettings()
            SettingsCard(title: "Presentations") {
                SettingsToggle("Show keystrokes", "For demos and screen sharing. Needs Input Monitoring. Nothing is stored.", isOn: $keystrokeHUD, needs: .inputMonitoring)
                if keystrokeHUD { SettingsToggle("Shortcuts only, never plain typing", isOn: $shortcutsOnly) }
            }
            SettingsCard(title: "Activity counter") {
                SettingsToggle("Count clicks, keystrokes and mouse distance", "Needs Input Monitoring. Only totals per day are kept, on this Mac, for 7 days. Never which keys.", isOn: $activityCounter, needs: .inputMonitoring)
                if activityCounter {
                    ActivityCounterCard().overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 12) }
                    SettingsRow(title: "Reset the counts") { Button("Reset", role: .destructive) { ActivityCounter.shared.reset() }.controlSize(.small) }
                }
            }
        }
    }

    private var menuBar: some View {
        SettingsPage(pane: .menuBar) {
            SettingsCard(title: "Menu bar") {
                SettingsToggle("Hide menu bar icons", "Adds a divider: ⌘-drag icons to its left, then click the chevron to hide them.", isOn: $hideMenuBarIcons)
                SettingsToggle("Next calendar event in the menu bar", "Needs Calendars access.", isOn: $menuBarCalendar)
                ForEach(MenuBarDetach.detachable) { tab in DetachToggle(tab: tab) }
            }
            SettingsCard(title: "Desktop and keyboard") {
                SettingsToggle("Desktop widgets", "Clock, world clock, weather and music on the desktop.", isOn: $desktopWidgets)
                SettingsToggle("Hyper key", "Caps Lock becomes ⌃⌥⇧⌘. Needs Accessibility.", isOn: $hyperKey, needs: .accessibility)
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
                            .onSubmit { saveKey() }
                        Button("Save key") { saveKey() }.disabled(apiKey.isEmpty)
                        if keySaved { Button("Remove key") { Keychain.delete(AskModel.keyService); keySaved = false } }
                    }.controlSize(.small)
                }
            }
            SettingsNote("Only the text recognised in the area you pick is sent to Anthropic, never the picture. Needs Screen Recording.")
        }
    }

    private var developer: some View {
        SettingsPage(pane: .developer) {
            SettingsCard(title: "Developer API") {
                SettingsToggle("Enable local API", "Scripts and AI apps on this Mac can then reach Pillbox, with a private token.", isOn: $devAPI)
                    .onChange(of: devAPI) { _, _ in DevAPI.shared.apply() }
                if devAPI {
                    SettingsRow(title: "Token", subtitle: "Scripts and hooks read it from the Keychain. Regenerating it breaks the ones that hold the old token.") {
                        Button("Regenerate") { DevAPI.regenerateToken() }.controlSize(.small)
                    }
                    SettingsRow(title: "Address", subtitle: "Reachable from this Mac only.") {
                        Text(verbatim: "127.0.0.1:\(DevAPI.defaultPort)").font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsStyle.dim).textSelection(.enabled)
                    }
                    copyRow("Copy MCP configuration") {
                        MCPServer.configuration(executable: Bundle.main.executablePath ?? "/Applications/Pillbox.app/Contents/MacOS/Pillbox")
                    }
                    copyRow("Copy Claude Code turn-summary hook") {
                        Self.hookJSON(event: "Stop", command: Bundle.main.path(forResource: "claude-stop-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-stop-hook.sh", timeout: 10)
                    }
                    copyRow("Copy Claude Code approval hook") {
                        Self.hookJSON(event: "PreToolUse", matcher: "Bash|Write|Edit", command: Bundle.main.path(forResource: "claude-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-hook.sh", timeout: 130)
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

    /// A Claude Code hook entry as JSON. JSONSerialization escapes the command, so a quote in the path cannot break the output.
    static func hookJSON(event: String, matcher: String? = nil, command: String, timeout: Int) -> String {
        var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
        if let matcher { entry["matcher"] = matcher }
        let root: [String: Any] = ["hooks": [event: [entry]]]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static let zshHook = """
    # Pillbox: show an island when a command runs longer than 15 s
    autoload -Uz add-zsh-hook
    _pillbox_pre() { _pb_cmd="$1"; _pb_t=$SECONDS }
    _pillbox_post() { local s=$? d=$((SECONDS-${_pb_t:-$SECONDS})); [ -n "$_pb_cmd" ] && [ $d -ge 15 ] && curl -s -m 2 -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H "Authorization: Bearer $(security find-generic-password -s dev.labs.pillbox.devapi -w)" -d "{\\"title\\":\\"Command finished (${d}s)\\",\\"message\\":\\"${_pb_cmd:0:80}\\",\\"symbol\\":\\"terminal.fill\\",\\"duration\\":5}" >/dev/null 2>&1 &!; _pb_cmd= }
    add-zsh-hook preexec _pillbox_pre; add-zsh-hook precmd _pillbox_post
    """

    private var shortcuts: some View {
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

    private var permissions: some View {
        SettingsPage(pane: .permissions) { PermissionsCard() }
    }

    private var about: some View {
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

/// The AI usage providers: which ones the tab shows, and in what order. Arrows move a provider; the switch hides it.
struct AIUsageOrderRows: View {
    @AppStorage(AIUsageService.orderKey) private var order = AIUsageService.allNames.joined(separator: ",")
    @AppStorage(AIUsageService.hiddenKey) private var hidden = ""

    /// Stored order first, then any provider the stored order does not mention yet.
    /// Names a provider that no longer exists are dropped here, so they are not kept in the stored lists.
    private var names: [String] {
        let stored = order.split(separator: ",").map(String.init).filter { AIUsageService.allNames.contains($0) }
        return stored + AIUsageService.allNames.filter { !stored.contains($0) }
    }

    private var hiddenSet: Set<String> { Set(hidden.split(separator: ",").map(String.init).filter { AIUsageService.allNames.contains($0) }) }

    var body: some View {
        ForEach(Array(names.enumerated()), id: \.element) { index, name in
            SettingsRow(title: LocalizedStringKey(name)) {
                HStack(spacing: 6) {
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0).accessibilityLabel(Text("Move up"))
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == names.count - 1).accessibilityLabel(Text("Move down"))
                    Toggle("", isOn: Binding(get: { !hiddenSet.contains(name) }, set: { setShown(name, $0) }))
                        .labelsHidden().toggleStyle(.switch).tint(SettingsStyle.accent)
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func move(_ index: Int, by step: Int) {
        var list = names
        let target = index + step
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        order = list.joined(separator: ",")
    }

    private func setShown(_ name: String, _ shown: Bool) {
        var set = hiddenSet
        if shown { set.remove(name) } else { set.insert(name) }
        hidden = set.sorted().joined(separator: ",")
    }
}
