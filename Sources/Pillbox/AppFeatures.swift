import Foundation

/// A feature of the app. It starts once at launch, then applies its settings at launch and again whenever one of its
/// keys changes. `apply` must be safe to repeat. A feature with no keys applies only at launch.
@MainActor
struct AppFeature {
    let name: String
    /// The settings keys the feature reads. Leaving one out means a change to it is not applied until something else changes.
    var keys: [String] = []
    var start: @MainActor () -> Void = {}
    var apply: @MainActor () -> Void = {}
}

/// Re-applies a feature only when one of its keys changed since the last time. Every settings change reaches every
/// feature, so without this each switch would reconfigure the whole app.
@MainActor
final class FeatureRouter {
    private let features: [AppFeature]
    /// What each feature's keys held the last time it was applied, by feature name.
    private var seen: [String: String] = [:]

    init(_ features: [AppFeature]) { self.features = features }

    /// Records the current values without applying anything. Called once at launch, after the features started.
    func prime() {
        for feature in features { seen[feature.name] = signature(feature) }
    }

    /// Applies the features whose keys changed since they were last applied.
    func applyChanged() {
        for feature in features {
            let now = signature(feature)
            guard now != seen[feature.name] else { continue }
            seen[feature.name] = now
            feature.apply()
        }
    }

    private func signature(_ feature: AppFeature) -> String {
        let defaults = UserDefaults.standard
        return feature.keys.map { "\($0)=\(String(describing: defaults.object(forKey: $0)))" }.joined(separator: "&")
    }
}

/// Every feature, in launch order. The menu bar icon and the shortcuts need the app delegate, so they are added there.
@MainActor
enum AppFeatures {
    static let all: [AppFeature] = [
        // First, so it has seen a lock or a sleep that began before the timers of the other features ran.
        AppFeature(name: "power gate", start: { _ = PowerGate.shared }),
        AppFeature(name: "music", start: { MusicService.shared.start() }),
        AppFeature(name: "clipboard", start: { ClipboardService.shared.start() }),
        AppFeature(name: "battery", start: { BatteryService.shared.start() }),
        AppFeature(name: "battery log", start: { BatteryLog.shared.start() }),
        AppFeature(name: "bluetooth islands", apply: { BluetoothIslands.shared.apply() }),
        AppFeature(name: "calendar", start: { CalendarService.shared.watch() }),
        AppFeature(name: "downloads", start: { DownloadsWatcher.shared.start() }),
        AppFeature(name: "screenshots", start: { ScreenshotWatcher.shared.start() }),
        AppFeature(name: "drives", start: { DriveWatcher.shared.start() }),
        AppFeature(name: "caps lock island", start: { SystemActions.startCapsLockHUD() }),
        AppFeature(name: "keystroke island", start: { KeystrokeHUD.shared.start() }),
        AppFeature(name: "brightness island", start: { BrightnessHUD.shared.start() }),
        AppFeature(name: "break reminder", start: { BreakReminder.shared.start() }),
        AppFeature(name: "notifications", start: { NotificationFeed.shared.start() }),
        AppFeature(name: "download progress", start: { DownloadProgress.shared.start() }),
        AppFeature(name: "build watcher", start: { BuildWatcher.shared.start() }),
        AppFeature(name: "focus monitor", start: { FocusMonitor.shared.start() }),
        AppFeature(name: "call monitor", start: { CallMonitor.shared.start() }),
        AppFeature(name: "focus guard", start: { FocusGuard.shared.start() }),
        AppFeature(name: "space watcher", start: { SpaceWatcher.shared.start() }),
        AppFeature(name: "hyper key", keys: [Preferences.hyperKey.key], apply: { HyperKey.shared.apply() }),
        AppFeature(name: "menu bar hider", keys: [Preferences.hideMenuBarIcons.key], apply: { MenuBarHider.shared.apply() }),
        AppFeature(name: "menu bar tabs", keys: ["detachedTabs"], apply: { MenuBarDetach.shared.apply() }),
        AppFeature(name: "menu bar calendar", keys: [Preferences.menuBarCalendar.key], apply: { MenuBarCalendar.shared.apply() }),
        AppFeature(name: "live spectrum", keys: [Preferences.liveSpectrum.key], apply: { AudioSpectrum.shared.apply() }),
        AppFeature(name: "double-tap", keys: [Preferences.doubleTapOpen.key], apply: { DoubleTapKey.shared.apply() }),
        AppFeature(name: "desktop widgets", keys: [Preferences.desktopWidgets.key], apply: { DesktopWidgets.shared.apply() }),
        AppFeature(name: "activity counter", keys: [Preferences.activityCounter.key], apply: { ActivityCounter.shared.apply() }),
        AppFeature(name: "idle collapse", start: { IdleCollapse.shared.start() }),
        AppFeature(name: "pointer hider", keys: [PointerHider.key], apply: { PointerHider.shared.apply() }),
        AppFeature(name: "eye breaks", start: { EyeBreaks.shared.start() }),
        AppFeature(name: "typing sounds", keys: [TypingSounds.profileKey, TypingSounds.volumeKey], apply: { TypingSounds.shared.apply() }),
        AppFeature(name: "updates", start: { Updater.shared.start() }),
        AppFeature(name: "homebrew updates", start: { BrewUpdates.shared.start() }),
        AppFeature(name: "calendar feeds", start: { ICSFeeds.shared.start() }),
        AppFeature(name: "extra brightness", keys: [Preferences.extraBrightness.key],
                   start: { ExtraBrightness.shared.start() }, apply: { ExtraBrightness.shared.apply() }),
        AppFeature(name: "window drag", keys: [Preferences.windowDrag.key], apply: { WindowDrag.shared.apply() }),
        AppFeature(name: "system equalizer", keys: [Preferences.systemEQ.key, Preferences.eqBass.key, Preferences.eqMid.key, Preferences.eqTreble.key],
                   apply: { if #available(macOS 14.2, *) { EqualizerService.shared.apply() } }),
        AppFeature(name: "local API", apply: { DevAPI.shared.apply() }),
        AppFeature(name: "privacy indicator", start: { PrivacyService.shared.start() }),
        AppFeature(name: "weather", start: { WeatherService.shared.start() }),
        AppFeature(name: "stocks", start: { StocksService.shared.start() }),
        AppFeature(name: "AI usage", start: { AIUsageService.shared.start() }),
        AppFeature(name: "reminders", start: { RemindersService.shared.watch() }),
        AppFeature(name: "volume island", start: { AudioControl.shared.startVolumeHUD() }),
        AppFeature(name: "appearance", keys: [Preferences.appearance.key], apply: { SettingsWindow.applyTheme() }),
    ]
}
