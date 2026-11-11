import Foundation

/// A preference stored in UserDefaults, with the one default every reader falls back to. The Settings switch and the code that
/// reads the value take it from here, so the two cannot drift apart.
struct Preference<Value: Sendable>: Sendable {
    let key: String
    let defaultValue: Value

    init(_ key: String, _ defaultValue: Value) { self.key = key; self.defaultValue = defaultValue }

    /// The stored value, or the default while the key was never set.
    var value: Value { UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
}

/// Every preference that Settings edits. Add one here and the switch can use it at once.
enum Preferences {
    static let hoverOpen = Preference<Bool>("hoverOpen", true)
    static let hoverDelay = Preference<Double>("hoverDelay", 0.12)
    static let capsHUD = Preference<Bool>("capsHUD", true)
    static let downloadAlerts = Preference<Bool>("downloadAlerts", true)
    static let privacyIndicator = Preference<Bool>("privacyIndicator", true)
    static let volumeHUD = Preference<Bool>("volumeHUD", true)
    static let keystrokeHUD = Preference<Bool>("keystrokeHUD", false)
    static let hideFromCapture = Preference<Bool>("hideFromCapture", false)
    static let hideEverywhere = Preference<Bool>("hideEverywhere", false)
    static let hideNotch = Preference<Bool>("hideNotch", false)
    static let searchEngine = Preference<String>("searchEngine", "google")
    static let hyperKey = Preference<Bool>("hyperKey", false)
    static let hyperEscape = Preference<Bool>("hyperEscape", true)
    static let hideMenuBarIcons = Preference<Bool>("hideMenuBarIcons", false)
    static let menuBarCalendar = Preference<Bool>("menuBarCalendar", false)
    static let liveSpectrum = Preference<Bool>("liveSpectrum", false)
    static let doubleTapOpen = Preference<Bool>("doubleTapOpen", false)
    static let snapZones = Preference<Bool>("snapZones", false)
    static let peekOnHover = Preference<Bool>("peekOnHover", false)
    static let desktopWidgets = Preference<Bool>("desktopWidgets", false)
    static let brightnessHUD = Preference<Bool>("brightnessHUD", true)
    static let extraBrightness = Preference<Bool>(ExtraBrightness.key, false)
    static let windowDrag = Preference<Bool>(WindowDrag.key, false)
    static let systemEQ = Preference<Bool>(EqualizerKeys.key, false)
    static let eqBass = Preference<Double>(EqualizerKeys.bassKey, 0.0)
    static let eqMid = Preference<Double>(EqualizerKeys.midKey, 0.0)
    static let eqTreble = Preference<Double>(EqualizerKeys.trebleKey, 0.0)
    static let focusIsland = Preference<Bool>("focusIsland", true)
    static let callIsland = Preference<Bool>("callIsland", true)
    static let hudStyle = Preference<String>("hudStyle", "notch")
    static let usageAlert = Preference<Int>("usageAlert", 0)
    static let panelScale = Preference<Double>("panelScale", 1.0)
    static let copyStack = Preference<Bool>("copyStack", false)
    static let islandTheme = Preference<String>("islandTheme", "black")
    static let doubleClickAction = Preference<String>("doubleClickAction", "none")
    static let tripleClickAction = Preference<String>("tripleClickAction", "none")
    static let notificationIsland = Preference<Bool>("notificationIsland", false)
    static let shakeToOpen = Preference<Bool>("shakeToOpen", true)
    static let breakReminder = Preference<Int>("breakReminder", 0)
    static let buildIsland = Preference<Bool>("buildIsland", true)
    static let hideInFullScreen = Preference<Bool>("hideInFullScreen", false)
    static let targetDisplay = Preference<String>("targetDisplay", "")
    static let mascot = Preference<String>("mascot", "none")
    static let lottiePath = Preference<String>("lottiePath", "")
    static let screenshotShelf = Preference<Bool>("screenshotShelf", true)
    static let driveEject = Preference<Bool>("driveEject", true)
    static let shortcutsOnly = Preference<Bool>("shortcutsOnly", true)
    static let fullCharge = Preference<Int>("fullChargeLevel", 100)
    static let drainAlert = Preference<Int>("drainAlert", 0)
    static let bluetoothIsland = Preference<Bool>("bluetoothIsland", false)
    static let pillWidth = Preference<Double>("pillWidth", 170.0)
    static let devAPI = Preference<Bool>("devAPIEnabled", false)
    static let appearance = Preference<String>("appearance", "system")
    static let showMenuBarIcon = Preference<Bool>("showMenuBarIcon", true)
    static let dictationShortcut = Preference<Bool>("dictationShortcut", false)
    static let activityCounter = Preference<Bool>("activityCounter", false)
    static let idleClock = Preference<Bool>(IdlePill.key, false)
    static let hapticIsland = Preference<Bool>(Haptics.key, false)
    static let idleCollapse = Preference<Int>(IdleCollapse.key, 0)
    static let hidePointer = Preference<Int>(PointerHider.key, 0)
    static let hideWhileMirroring = Preference<Bool>(Mirroring.key, false)
    static let swipeSpaces = Preference<Bool>(SpaceSwipe.key, false)
    static let eyeBreaks = Preference<Bool>(EyeBreaks.key, false)
    static let codeIsland = Preference<Bool>(NotificationFeed.codeIslandKey, true)
    static let autoUpdate = Preference<Bool>(Updater.autoKey, false)
    static let betaUpdates = Preference<Bool>(Updater.betaKey, false)
    static let brewUpdates = Preference<Bool>(BrewUpdates.key, false)
    static let copilotUsage = Preference<Bool>(AIUsageService.copilotKey, false)
    static let typingProfile = Preference<String>(TypingSounds.profileKey, "off")
    static let typingVolume = Preference<Double>(TypingSounds.volumeKey, 0.5)
    static let ambientKind = Preference<String>(AmbientNoise.kindKey, "off")
    static let ambientVolume = Preference<Double>(AmbientNoise.volumeKey, 0.3)
    static let focusBlocking = Preference<Bool>("focusBlocking", false)
    static let spaceIsland = Preference<Bool>("spaceIsland", false)
    static let cameraGuard = Preference<Bool>("cameraGuard", false)
    /// Read by the idle animation: 1× unless changed. Clamped to 0.1× at the reader, so a stored 0 never freezes it.
    static let lottieSpeed = Preference<Double>("lottieSpeed", 1.0)
    /// Seconds the hidden menu bar icons stay visible after a click on the chevron; 0 keeps them until clicked again.
    static let menuBarAutoHide = Preference<Int>("menuBarAutoHide", 0)
    /// Hours ahead within which the next event shows in the menu bar; 0 shows it always.
    static let menuBarCalendarHours = Preference<Int>("menuBarCalendarHours", 0)
    /// The hour the quiet period starts (0 to 23), or -1 for none. Islands that are not urgent wait during it.
    static let quietFrom = Preference<Int>("quietFrom", -1)
    /// The hour the quiet period ends (0 to 23).
    static let quietTo = Preference<Int>("quietTo", 7)
    /// Days an entry stays on the shelf before it is dropped from it; 0 keeps entries until removed by hand.
    static let shelfKeepDays = Preference<Int>("shelfKeepDays", 0)
    /// Minutes before a secret copy (an API key or a card number) leaves the clipboard history; 0 keeps it until removed by hand.
    static let clipboardSecretMinutes = Preference<Int>("clipboardSecretMinutes", 5)
    /// Show the music or video playing in a browser tab on the Music tab. Off by default: it asks the browser for its tab.
    static let browserMusic = Preference<Bool>("browserMusic", false)
    /// Point size of the Terminal tab's text, 10 to 18. Clamped at the reader.
    static let terminalFontSize = Preference<Int>("terminalFontSize", TerminalLook.defaultFontSize)
    /// Colors of the Terminal tab: "dark" (the default) or "light".
    static let terminalTheme = Preference<String>("terminalTheme", TerminalTheme.dark.rawValue)
}
