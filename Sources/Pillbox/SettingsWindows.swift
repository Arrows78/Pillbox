import AppKit
import SwiftUI
import ServiceManagement

/// The Windows and keyboard pane: moving and snapping windows, the copy stack, swipes, the hyper key and desktop widgets.
struct SettingsWindowsPane: View {
    @AppStorage(Preferences.hyperKey.key) private var hyperKey = Preferences.hyperKey.defaultValue
    @AppStorage(Preferences.hyperEscape.key) private var hyperEscape = Preferences.hyperEscape.defaultValue
    @AppStorage(Preferences.doubleTapOpen.key) private var doubleTapOpen = Preferences.doubleTapOpen.defaultValue
    @AppStorage(Preferences.snapZones.key) private var snapZones = Preferences.snapZones.defaultValue
    @AppStorage(Preferences.desktopWidgets.key) private var desktopWidgets = Preferences.desktopWidgets.defaultValue
    @AppStorage(Preferences.windowDrag.key) private var windowDrag = Preferences.windowDrag.defaultValue
    @AppStorage(Preferences.copyStack.key) private var copyStack = Preferences.copyStack.defaultValue
    @AppStorage(Preferences.swipeSpaces.key) private var swipeSpaces = Preferences.swipeSpaces.defaultValue

    var body: some View {
        SettingsPage(pane: .windows) {
            SettingsCard(title: "Windows and keyboard") {
                SettingsToggle("Swipe the resting pill to change desktop", "Two fingers left or right on the pill. Needs Accessibility.", isOn: $swipeSpaces, needs: .accessibility)
                SettingsToggle("Move and resize windows with the mouse", "Hold ⌃⌥ and drag a window to move it; add ⇧ to resize it. Needs Accessibility.", isOn: $windowDrag, needs: .accessibility)
                SettingsToggle("Snap zones when dragging a window to the notch", "Needs Accessibility. Drop the window on a zone to tile it.", isOn: $snapZones, needs: .accessibility)
                SettingsToggle("Double-press Control to open the notch", "Needs Input Monitoring.", isOn: $doubleTapOpen, needs: .inputMonitoring)
                SettingsToggle("Copy stack", "Copy several things, then paste them one by one, in order, with the Paste next shortcut.", isOn: $copyStack)
            }
            SettingsCard(title: "Desktop and keyboard") {
                SettingsToggle("Desktop widgets", "Clock, world clock, weather and music on the desktop.", isOn: $desktopWidgets)
                SettingsToggle("Hyper key", "Caps Lock becomes ⌃⌥⇧⌘. Needs Accessibility.", isOn: $hyperKey, needs: .accessibility)
                if hyperKey { SettingsToggle("A quick press sends Escape", isOn: $hyperEscape) }
            }
        }
    }
}
