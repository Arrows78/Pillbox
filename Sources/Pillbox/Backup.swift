import AppKit

/// Export, import and reset of the preferences. Only the keys listed here are ever read or written, and an imported
/// value must have the right type and range, so a hand-edited or foreign file can do no harm.
/// Left out on purpose: the local API switch and token, the Anthropic key (Keychain), and the data kept in
/// Application Support (clipboard history, notes, shelf, quick actions, which can hold shell commands).
enum SettingsBackup {
    enum Kind {
        case bool
        case number(ClosedRange<Double>)
        case text([String]?)   // nil accepts any text, a list restricts the value to it
        case textList         // a comma-separated list of names
        case equalizer        // per-app bass, mid and treble: three values each, in -12...12 dB
    }

    static var keys: [String: Kind] {
        var k: [String: Kind] = [:]
        for key in ["hoverOpen", "capsHUD", "downloadAlerts", "privacyIndicator", "volumeHUD", "keystrokeHUD", "hideFromCapture", "hideEverywhere", "hideNotch",
                    "hyperKey", "hyperEscape", "hideMenuBarIcons", "menuBarCalendar", "liveSpectrum", "doubleTapOpen", "snapZones", "peekOnHover",
                    "desktopWidgets", "brightnessHUD", "focusIsland", "callIsland", "copyStack", "notificationIsland", "shakeToOpen", "buildIsland",
                    "hideInFullScreen", "screenshotShelf", ExtraBrightness.key, WindowDrag.key, "driveEject", "shortcutsOnly", "showMenuBarIcon"] { k[key] = .bool }
        for key in ["dictationShortcut", "activityCounter", "focusBlocking", "spaceIsland", "cameraGuard", "bluetoothIsland"] { k[key] = .bool }
        for key in [IdlePill.key, Haptics.key, Mirroring.key, SpaceSwipe.key, EyeBreaks.key, NotificationFeed.codeIslandKey, Updater.autoKey, Updater.betaKey, BrewUpdates.key, AIUsageService.copilotKey] { k[key] = .bool }
        k[TypingSounds.profileKey] = .text(TypingSounds.Profile.allCases.map(\.rawValue))
        k[AmbientNoise.kindKey] = .text(AmbientNoise.Kind.allCases.map(\.rawValue))
        k[TypingSounds.volumeKey] = .number(0...1); k[AmbientNoise.volumeKey] = .number(0...1)
        k[IdleCollapse.key] = .number(0...600)
        k[PointerHider.key] = .number(0...120)
        k[Tab.hiddenKey] = .text(nil); k[Tab.orderKey] = .text(nil)
        k["hoverDelay"] = .number(0.05...0.6)
        k["panelScale"] = .number(0.8...1.3)
        k["pillWidth"] = .number(120...260)
        k["fullChargeLevel"] = .number(80...100)
        k["usageAlert"] = .number(0...100)
        k["drainAlert"] = .number(0...100)
        k[AppVolumeService.eqKey] = .equalizer
        k[AIUsageService.orderKey] = .text(nil); k[AIUsageService.hiddenKey] = .text(nil)
        k["breakReminder"] = .number(0...240)
        k["playerSize"] = .number(160...400)
        k["lottieSpeed"] = .number(0.1...4)
        k["searchEngine"] = .text(WebSearch.engines.map(\.key))
        k["hudStyle"] = .text(["notch", "edge", "circle"])
        k["islandTheme"] = .text(IslandTheme.allCases.map(\.rawValue))
        k["doubleClickAction"] = .text(PillAction.allCases.map(\.rawValue))
        k["tripleClickAction"] = .text(PillAction.allCases.map(\.rawValue))
        k["mascot"] = .text(Mascot.allCases.map(\.rawValue))
        k["appearance"] = .text(["system", "light", "dark"])
        k["targetDisplay"] = .text(nil)
        k["lottiePath"] = .text(nil)
        k["pinnedStock"] = .text(nil)
        k["detachedTabs"] = .textList
        k[HomeLayout.cardsKey] = .text(nil); k[HomeLayout.tilesKey] = .text(nil); k[HomeLayout.gaugesKey] = .text(nil)   // unknown names are skipped when read
        return k
    }

    private static let marker = "pillbox-settings"

    /// A value of the right type and range for `kind`, or nil.
    static func accepted(_ value: Any, _ kind: Kind) -> Any? {
        let isBool = CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
        switch kind {
        case .bool: return isBool ? value : nil
        case .number(let range):
            guard !isBool, let n = value as? NSNumber, n.doubleValue.isFinite else { return nil }
            let c = min(max(n.doubleValue, range.lowerBound), range.upperBound)
            return c == c.rounded() ? Int(c) as Any : c as Any
        case .text(let allowed):
            guard let s = value as? String, allowed?.contains(s) ?? true else { return nil }
            return s
        case .textList:
            guard let a = value as? [String] else { return nil }
            return a
        case .equalizer:
            guard let bands = value as? [String: [Double]],
                  bands.values.allSatisfy({ $0.count == 3 && $0.allSatisfy { (-12...12).contains($0) } }) else { return nil }
            return bands
        }
    }

    static func data(from store: UserDefaults = .standard) -> Data? {
        var settings: [String: Any] = [:]
        for key in keys.keys { if let v = store.object(forKey: key) { settings[key] = v } }
        let file: [String: Any] = ["format": marker, "version": 1, "settings": settings]
        return try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
    }

    /// Applies a backup; returns how many settings were restored, or nil when the file is not a Pillbox backup.
    @discardableResult
    static func restore(_ data: Data, into store: UserDefaults = .standard) -> Int? {
        guard let file = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              file["format"] as? String == marker, let settings = file["settings"] as? [String: Any] else { return nil }
        let known = keys
        var count = 0
        for (key, value) in settings {
            guard let kind = known[key], let ok = accepted(value, kind) else { continue }
            store.set(ok, forKey: key); count += 1
        }
        return count
    }

    /// Every setting back to its default (the code's defaults apply again once the stored value is gone).
    static func resetAll(in store: UserDefaults = .standard) {
        for key in keys.keys { store.removeObject(forKey: key) }
    }
}
