import AppKit
import SwiftUI
import ServiceManagement

/// The Alerts pane: the system and activity islands, AI usage limits and the break reminders.
struct SettingsAlertsPane: View {
    @AppStorage(Preferences.quietFrom.key) private var quietFrom = Preferences.quietFrom.defaultValue
    @AppStorage(Preferences.quietTo.key) private var quietTo = Preferences.quietTo.defaultValue
    @AppStorage(Preferences.capsHUD.key) private var capsHUD = Preferences.capsHUD.defaultValue
    @AppStorage(Preferences.downloadAlerts.key) private var downloadAlerts = Preferences.downloadAlerts.defaultValue
    @AppStorage(Preferences.privacyIndicator.key) private var privacyIndicator = Preferences.privacyIndicator.defaultValue
    @AppStorage(Preferences.volumeHUD.key) private var volumeHUD = Preferences.volumeHUD.defaultValue
    @AppStorage(Preferences.keystrokeHUD.key) private var keystrokeHUD = Preferences.keystrokeHUD.defaultValue
    @AppStorage(Preferences.brightnessHUD.key) private var brightnessHUD = Preferences.brightnessHUD.defaultValue
    @AppStorage(Preferences.extraBrightness.key) private var extraBrightness = Preferences.extraBrightness.defaultValue
    @AppStorage(Preferences.focusIsland.key) private var focusIsland = Preferences.focusIsland.defaultValue
    @AppStorage(Preferences.callIsland.key) private var callIsland = Preferences.callIsland.defaultValue
    @AppStorage(Preferences.usageAlert.key) private var usageAlert = Preferences.usageAlert.defaultValue
    @AppStorage(Preferences.notificationIsland.key) private var notificationIsland = Preferences.notificationIsland.defaultValue
    @AppStorage(Preferences.breakReminder.key) private var breakReminder = Preferences.breakReminder.defaultValue
    @AppStorage(Preferences.pomodoroEvery.key) private var pomodoroEvery = Preferences.pomodoroEvery.defaultValue
    @AppStorage(Preferences.pomodoroLongBreak.key) private var pomodoroLongBreak = Preferences.pomodoroLongBreak.defaultValue
    @AppStorage(Preferences.timerSound.key) private var timerSound = Preferences.timerSound.defaultValue
    @AppStorage(Preferences.rainAlert.key) private var rainAlert = Preferences.rainAlert.defaultValue
    @AppStorage(Preferences.buildIsland.key) private var buildIsland = Preferences.buildIsland.defaultValue
    @AppStorage(Preferences.screenshotShelf.key) private var screenshotShelf = Preferences.screenshotShelf.defaultValue
    @AppStorage(Preferences.driveEject.key) private var driveEject = Preferences.driveEject.defaultValue
    @AppStorage(Preferences.shortcutsOnly.key) private var shortcutsOnly = Preferences.shortcutsOnly.defaultValue
    @AppStorage(Preferences.fullCharge.key) private var fullCharge = Preferences.fullCharge.defaultValue
    @AppStorage(Preferences.drainAlert.key) private var drainAlert = Preferences.drainAlert.defaultValue
    @AppStorage(Preferences.bluetoothIsland.key) private var bluetoothIsland = Preferences.bluetoothIsland.defaultValue
    @AppStorage(Preferences.activityCounter.key) private var activityCounter = Preferences.activityCounter.defaultValue
    @AppStorage(Preferences.eyeBreaks.key) private var eyeBreaks = Preferences.eyeBreaks.defaultValue
    @AppStorage(Preferences.codeIsland.key) private var codeIsland = Preferences.codeIsland.defaultValue
    @AppStorage(Preferences.brewUpdates.key) private var brewUpdates = Preferences.brewUpdates.defaultValue
    @AppStorage(Preferences.copilotUsage.key) private var copilotUsage = Preferences.copilotUsage.defaultValue

    var body: some View {
        SettingsPage(pane: .alerts) {
            SettingsCard(title: "Weather") {
                SettingsToggle("Rain expected soon", "An island when the forecast gives 60% or more chance of rain in the next hours.", isOn: $rainAlert)
            }
            SettingsCard(title: "Quiet hours") {
                SettingsRow(title: "From", subtitle: "Islands wait between these hours. Urgent ones still show.") {
                    Picker("", selection: $quietFrom) { Text("Off").tag(-1); ForEach(0..<24, id: \.self) { Text(verbatim: "\($0):00").tag($0) } }
                        .labelsHidden().frame(width: 110)
                }
                SettingsRow(title: "Until", subtitle: "The islands come back at this hour.") {
                    Picker("", selection: $quietTo) { ForEach(0..<24, id: \.self) { Text(verbatim: "\($0):00").tag($0) } }
                        .labelsHidden().frame(width: 110)
                }
            }
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
                SettingsRow(title: "Long break after", subtitle: "Pomodoro: after this many focus sessions, the break is the long one.") {
                    Picker("", selection: $pomodoroEvery) {
                        Text("Off").tag(0); Text("2 sessions").tag(2); Text("3 sessions").tag(3); Text("4 sessions").tag(4); Text("5 sessions").tag(5)
                    }.labelsHidden().frame(width: 170)
                }
                SettingsRow(title: "Timer sound", subtitle: "Plays when a timer or a focus session ends.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $timerSound) { ForEach(FocusExport.sounds, id: \.self) { Text(verbatim: $0).tag($0) } }
                            .labelsHidden().frame(width: 130)
                        Button("Try") { NSSound(named: timerSound)?.play() }.controlSize(.small)
                    }
                }
                SettingsRow(title: "Export focus sessions…", subtitle: "A CSV file with the focus sessions of each day, for a spreadsheet.") {
                    Button("Export…") { FocusExport.save(TimerService.shared.sessions) }.controlSize(.small)
                }
                if pomodoroEvery > 0 {
                    SettingsRow(title: "Long break length") {
                        Picker("", selection: $pomodoroLongBreak) {
                            Text("10 min").tag(10); Text("15 min").tag(15); Text("20 min").tag(20); Text("30 min").tag(30)
                        }.labelsHidden().frame(width: 170)
                    }
                }
                SettingsToggle("Eye breaks (20-20-20)", "Every 20 minutes at the keyboard, 20 seconds to look at something far away, counted down on the island.", isOn: $eyeBreaks)
            }
            SettingsCard(title: "Islands") {
                ForEach(IslandKind.allCases) { IslandKindRow(kind: $0) }
            }
            SettingsNote("Low islands wait behind the others and are dropped while one is showing. High ones jump the queue. Duration is how long each stays on screen.")
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
}



/// One line of the Islands table: the kind, its priority and duration, and the switch that turns it off.
struct IslandKindRow: View {
    let kind: IslandKind
    @AppStorage private var on: Bool
    @AppStorage private var priority: String
    @AppStorage private var duration: Double

    init(kind: IslandKind) {
        self.kind = kind
        let on = Preferences.islandOn(kind), priority = Preferences.islandPriority(kind), duration = Preferences.islandDuration(kind)
        _on = AppStorage(wrappedValue: on.defaultValue, on.key)
        _priority = AppStorage(wrappedValue: priority.defaultValue, priority.key)
        _duration = AppStorage(wrappedValue: duration.defaultValue, duration.key)
    }

    var body: some View {
        SettingsRow(title: kind.title) {
            HStack(spacing: 10) {
                Picker("", selection: $priority) {
                    ForEach(Activity.Priority.all, id: \.key) { Text($0.title).tag($0.key) }
                }
                .labelsHidden().frame(width: 96).disabled(!on)
                HStack(spacing: 4) {
                    Text(verbatim: "\(duration.formatted(.number.precision(.fractionLength(0...1)))) s")
                        .monospacedDigit().foregroundStyle(SettingsStyle.dim).frame(width: 52, alignment: .trailing)
                    Stepper("", value: $duration, in: 1...30, step: 0.5).labelsHidden()
                }
                .disabled(!on)
                .opacity(on ? 1 : 0.5)
                Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch).tint(SettingsStyle.accent)
            }
            .buttonStyle(.borderless).controlSize(.small)
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
