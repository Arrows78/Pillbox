import AppKit
import SwiftUI
import ServiceManagement

/// The Island pane: how the island opens, what it shows at rest, its look and its gestures.
struct SettingsIslandPane: View {
    @AppStorage(Preferences.hoverOpen.key) private var hoverOpen = Preferences.hoverOpen.defaultValue
    @AppStorage(Preferences.hoverDelay.key) private var hoverDelay = Preferences.hoverDelay.defaultValue
    @AppStorage(Preferences.hideFromCapture.key) private var hideFromCapture = Preferences.hideFromCapture.defaultValue
    @AppStorage(Preferences.hideEverywhere.key) private var hideEverywhere = Preferences.hideEverywhere.defaultValue
    @AppStorage(Preferences.showMenuBarIcon.key) private var showMenuBarIcon = Preferences.showMenuBarIcon.defaultValue
    @AppStorage(Preferences.hideNotch.key) private var hideNotch = Preferences.hideNotch.defaultValue
    @AppStorage(Preferences.peekOnHover.key) private var peekOnHover = Preferences.peekOnHover.defaultValue
    @AppStorage(Preferences.hudStyle.key) private var hudStyle = Preferences.hudStyle.defaultValue
    @AppStorage(Preferences.panelScale.key) private var panelScale = Preferences.panelScale.defaultValue
    @AppStorage(Preferences.tabPanelSizes.key) private var tabPanelSizes = Preferences.tabPanelSizes.defaultValue
    @AppStorage(Preferences.islandTheme.key) private var islandTheme = Preferences.islandTheme.defaultValue
    @AppStorage(Preferences.doubleClickAction.key) private var doubleClickAction = Preferences.doubleClickAction.defaultValue
    @AppStorage(Preferences.tripleClickAction.key) private var tripleClickAction = Preferences.tripleClickAction.defaultValue
    @AppStorage(Preferences.shakeToOpen.key) private var shakeToOpen = Preferences.shakeToOpen.defaultValue
    @AppStorage(Preferences.hideInFullScreen.key) private var hideInFullScreen = Preferences.hideInFullScreen.defaultValue
    @AppStorage(Preferences.targetDisplay.key) private var targetDisplay = Preferences.targetDisplay.defaultValue
    @AppStorage(Preferences.mascot.key) private var mascot = Preferences.mascot.defaultValue
    @AppStorage(Preferences.lottiePath.key) private var lottiePath = Preferences.lottiePath.defaultValue
    @AppStorage(Preferences.pillWidth.key) private var pillWidth = Preferences.pillWidth.defaultValue
    @AppStorage(Preferences.idleClock.key) private var idleClock = Preferences.idleClock.defaultValue
    @AppStorage(Preferences.hapticIsland.key) private var hapticIsland = Preferences.hapticIsland.defaultValue
    @AppStorage(Preferences.idleCollapse.key) private var idleCollapse = Preferences.idleCollapse.defaultValue
    @AppStorage(Preferences.hidePointer.key) private var hidePointer = Preferences.hidePointer.defaultValue
    @AppStorage(Preferences.hideWhileMirroring.key) private var hideWhileMirroring = Preferences.hideWhileMirroring.defaultValue

    /// The Display picker's choice by screen position. Two identical monitors share a name, so the position is what tells them apart;
    /// the name stays in `targetDisplay`, which the island reads.
    private var displaySelection: Binding<String> {
        Binding(get: {
            NSScreen.screens.firstIndex { $0.localizedName == targetDisplay }.map { String($0) } ?? ""
        }, set: { tag in
            if let i = Int(tag), NSScreen.screens.indices.contains(i) { targetDisplay = NSScreen.screens[i].localizedName } else { targetDisplay = "" }
        })
    }

    /// The size one tab opens at, read from and written to the stored "tab=size" list.
    private func panelSize(of tab: Tab) -> Binding<PanelSize> {
        Binding(get: {
            PanelSize.sizes(from: tabPanelSizes)[tab] ?? .standard
        }, set: { size in
            var sizes = PanelSize.sizes(from: tabPanelSizes)
            sizes[tab] = size
            tabPanelSizes = PanelSize.setting(from: sizes)
        })
    }

    var body: some View {
        SettingsPage(pane: .island) {
            SettingsCard(title: "Notch") {
                SettingsToggle("Open when hovering the notch", isOn: $hoverOpen)
                if hoverOpen { SettingsRow(title: "Hover delay") { Slider(value: $hoverDelay, in: 0.05...0.6).frame(width: 180) } }
                SettingsToggle("Hide from screenshots and screen sharing", "Pillbox stays out of screenshots, recordings and screen sharing.", isOn: $hideFromCapture)
                SettingsToggle("Hide everywhere", "Also hides the island on your own screen, not only from captures. Its shortcuts keep working; open Settings from the menu bar icon to turn it back on.", isOn: $hideEverywhere)
                if hideEverywhere && !showMenuBarIcon {
                    Label(localized("Both are off: the island and the menu bar icon. Launch Pillbox again to open Settings."), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 12).padding(.bottom, 8)
                }
                SettingsToggle("Hide the notch (black menu bar)", "Paints the menu bar black so the notch disappears.", isOn: $hideNotch)
                if NotchModel.shared.geometry.screen?.safeAreaInsets.top == 0 {
                    SettingsRow(title: "Pill width", subtitle: "Width of the pill on a screen without a notch.") { Slider(value: $pillWidth, in: 120...260).frame(width: 180) }
                }
            }
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
                SettingsRow(title: "Hide the pointer when it rests", subtitle: "In every app, handy for films. Any movement brings it back.") {
                    Picker("", selection: $hidePointer) { Text("Never").tag(0); Text("5 s").tag(5); Text("10 s").tag(10); Text("30 s").tag(30) }.labelsHidden().frame(width: 170)
                }
                SettingsToggle("Show a mini player when hovering during playback", isOn: $peekOnHover)
                SettingsToggle("Shake a dragged file to open the shelf", isOn: $shakeToOpen)
            }
            SettingsCard(title: "Panel size per tab") {
                ForEach(Tab.allCases) { tab in
                    SettingsRow(title: LocalizedStringKey(tab.title)) {
                        Picker("", selection: panelSize(of: tab)) { ForEach(PanelSize.allCases) { Text(verbatim: $0.title).tag($0) } }.labelsHidden().frame(width: 170)
                    }
                }
            }
            SettingsNote("The size applies when the panel opens on that tab. Switching tabs keeps it. Panel size above scales every tab.")
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
}
