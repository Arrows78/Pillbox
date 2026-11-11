import Foundation

/// A feature that re-applies its settings when one of its keys changes. It lists every key it reads: a key left out
/// means a change to it is not applied until something else changes.
@MainActor
struct SettingsFeature {
    let name: String
    let keys: [String]
    let apply: @MainActor () -> Void
}

/// Re-applies a feature only when one of its keys changed since the last time. Every settings change reaches every
/// feature, so without this each switch would reconfigure the whole app.
@MainActor
final class SettingsFeatureRouter {
    private let features: [SettingsFeature]
    /// What each feature's keys held the last time it was applied, by feature name.
    private var seen: [String: String] = [:]

    init(_ features: [SettingsFeature]) { self.features = features }

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

    private func signature(_ feature: SettingsFeature) -> String {
        let defaults = UserDefaults.standard
        return feature.keys.map { "\($0)=\(String(describing: defaults.object(forKey: $0)))" }.joined(separator: "&")
    }
}

/// The features that re-apply on a settings change. The ones started at launch and the menu bar icon and shortcuts,
/// which need the app delegate, are added there.
@MainActor
enum SettingsFeatures {
    static let all: [SettingsFeature] = [
        SettingsFeature(name: "hyper key", keys: [Preferences.hyperKey.key]) { HyperKey.shared.apply() },
        SettingsFeature(name: "extra brightness", keys: [Preferences.extraBrightness.key]) { ExtraBrightness.shared.apply() },
        SettingsFeature(name: "window drag", keys: [Preferences.windowDrag.key]) { WindowDrag.shared.apply() },
        SettingsFeature(name: "system equalizer", keys: [Preferences.systemEQ.key, Preferences.eqBass.key, Preferences.eqMid.key, Preferences.eqTreble.key]) {
            if #available(macOS 14.2, *) { EqualizerService.shared.apply() }
        },
        SettingsFeature(name: "menu bar hider", keys: [Preferences.hideMenuBarIcons.key]) { MenuBarHider.shared.apply() },
        SettingsFeature(name: "menu bar tabs", keys: ["detachedTabs"]) { MenuBarDetach.shared.apply() },
        SettingsFeature(name: "menu bar calendar", keys: [Preferences.menuBarCalendar.key]) { MenuBarCalendar.shared.apply() },
        SettingsFeature(name: "live spectrum", keys: [Preferences.liveSpectrum.key]) { AudioSpectrum.shared.apply() },
        SettingsFeature(name: "double-tap", keys: [Preferences.doubleTapOpen.key]) { DoubleTapKey.shared.apply() },
        SettingsFeature(name: "desktop widgets", keys: [Preferences.desktopWidgets.key]) { DesktopWidgets.shared.apply() },
        SettingsFeature(name: "theme", keys: [Preferences.appearance.key]) { SettingsWindow.applyTheme() },
        SettingsFeature(name: "activity counter", keys: [Preferences.activityCounter.key]) { ActivityCounter.shared.apply() },
        SettingsFeature(name: "pointer hider", keys: [PointerHider.key]) { PointerHider.shared.apply() },
        SettingsFeature(name: "typing sounds", keys: [TypingSounds.profileKey, TypingSounds.volumeKey]) { TypingSounds.shared.apply() },
    ]
}
