import AppKit
import Carbon.HIToolbox

/// Carries a palette action through an NSMenuItem.
final class ActionBox {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) { self.run = run }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: NotchWindowController!
    private var statusItem: NSStatusItem!
    private var hotKeys: [GlobalShortcut: HotKey] = [:]
    private var monitors: [Any] = []
    private var interaction: IslandInteraction!
    /// The last app that was not Pillbox, so commands can act on it after a click on the status item.
    private var lastOtherApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchWindowController()
        // pkill and install.sh send SIGTERM, which skips applicationWillTerminate: route it there so Caps Lock is restored.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume(); sigterm = term
        MusicService.shared.start()
        ClipboardService.shared.start()
        BatteryService.shared.start()
        BatteryLog.shared.start()
        BluetoothIslands.shared.apply()
        CalendarService.shared.watch()
        DownloadsWatcher.shared.start()
        ScreenshotWatcher.shared.start()
        DriveWatcher.shared.start()
        SystemActions.startCapsLockHUD()
        KeystrokeHUD.shared.start()
        BrightnessHUD.shared.start()
        BreakReminder.shared.start()
        NotificationFeed.shared.start()
        DownloadProgress.shared.start()
        BuildWatcher.shared.start()
        FocusMonitor.shared.start()
        CallMonitor.shared.start()
        FocusGuard.shared.start()
        SpaceWatcher.shared.start()
        HyperKey.shared.apply()
        MenuBarHider.shared.apply()
        MenuBarDetach.shared.apply()
        MenuBarCalendar.shared.apply()
        AudioSpectrum.shared.apply()
        DoubleTapKey.shared.apply()
        DesktopWidgets.shared.apply()
        ActivityCounter.shared.apply()
        IdleCollapse.shared.start()
        PointerHider.shared.apply()
        EyeBreaks.shared.start()
        TypingSounds.shared.apply()
        Updater.shared.start()
        BrewUpdates.shared.start()
        ICSFeeds.shared.start()
        ExtraBrightness.shared.start()
        WindowDrag.shared.apply()
        if #available(macOS 14.2, *) { EqualizerService.shared.apply() }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyDefaultsFeatures()
                NotificationCenter.default.post(name: .notchStateChanged, object: nil)   // the idle clock changes the pill's shape
            }
        }
        DevAPI.shared.apply()
        PrivacyService.shared.start()
        WeatherService.shared.start()
        StocksService.shared.start()
        AIUsageService.shared.start()
        RemindersService.shared.watch()
        AudioControl.shared.startVolumeHUD()
        setupStatusItem()
        monitors.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        } as Any)
        setupMainMenu()
        if CommandLine.arguments.contains("--open-teleprompter") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Teleprompter.shared.show() } }
        if CommandLine.arguments.contains("--open-player") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { FloatingPlayer.shared.show() } }
        if CommandLine.arguments.contains("--open-lyrics") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { LyricsScreen.shared.show() } }
        // Debug aid: `Pillbox --open-menu` pops the menu-bar menu up in the middle of the screen (the icon may be hidden).
        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 400, y: 900), in: nil)
            }
        }
        // Debug aid: `Pillbox --open-settings ask` opens the settings window on a pane.
        if let i = CommandLine.arguments.firstIndex(of: "--open-settings") {
            let pane = CommandLine.arguments.indices.contains(i + 1) ? SettingsPane(rawValue: CommandLine.arguments[i + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindow.show(pane: pane ?? .general) }
        }
        if CommandLine.arguments.contains("--open-palette") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PaletteController.shared.show() } }
        // Debug aid: `Pillbox --open-tab ai` opens the notch on a tab and keeps it open (used to screenshot each tab).
        if let i = CommandLine.arguments.firstIndex(of: "--open-tab"), CommandLine.arguments.indices.contains(i + 1),
           let tab = Tab(rawValue: CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotchModel.shared.pinnedOpen = true; NotchModel.shared.expand(tab) }
        }
        // First launch: show the settings (permissions first) instead of letting prompts appear out of nowhere.
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            UserDefaults.standard.set(true, forKey: "onboarded")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SettingsWindow.show() }
        }
        interaction = IslandInteraction(controller: controller)
        interaction.start()
        applyHotKeys()
        // ⌘1–9 switches tabs while the notch is open.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard NotchModel.shared.expanded, e.modifierFlags.contains(.command),
                  let c = e.charactersIgnoringModifiers, let n = Int(c), (1...Tab.visible.count).contains(n) else { return e }
            NotchModel.shared.tab = Tab.visible[n - 1]; return nil
        } as Any)
        // Swipe left/right on the notch to change tab; on the resting pill (opt-in) to change desktop.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, abs(e.scrollingDeltaX) > 8, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 2,
                  e.phase == .began || e.phase == .changed, self.swipeCooldown < Date() else { return e }
            if !NotchModel.shared.expanded {
                guard UserDefaults.standard.bool(forKey: SpaceSwipe.key), NotchModel.shared.activity == nil else { return e }
                self.swipeCooldown = Date().addingTimeInterval(0.8)
                SpaceSwipe.go(left: e.scrollingDeltaX > 0); return nil
            }
            self.swipeCooldown = Date().addingTimeInterval(0.4)
            let tabs = Tab.visible, i = tabs.firstIndex(of: NotchModel.shared.tab) ?? 0
            let j = e.scrollingDeltaX < 0 ? min(i + 1, tabs.count - 1) : max(i - 1, 0)
            NotchModel.shared.tab = tabs[j]; return e
        } as Any)
    }

    private var swipeCooldown = Date.distantPast
    private var sigterm: DispatchSourceSignal?

    /// Caps Lock must never stay remapped after Pillbox quits.
    func applicationWillTerminate(_ notification: Notification) { HyperKey.shared.disable(); AudioSpectrum.shared.stop(); AppVolumeService.shared.stopAll(); ActivityCounter.shared.save() }

    /// Registers the enabled global shortcuts and releases the opt-in ones that were turned off.
    private func applyHotKeys() {
        for s in GlobalShortcut.allCases {
            if s.isEnabled, hotKeys[s] == nil {
                hotKeys[s] = HotKey(keyCode: s.keyCode, modifiers: GlobalShortcut.modifiers, id: s.rawValue) { s.run() }
            } else if !s.isEnabled, let h = hotKeys.removeValue(forKey: s) { h.unregister() }
        }
    }

    /// Launching Pillbox again opens Settings, which is the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show(); return true
    }

    func applyStatusItemVisibility() {
        statusItem?.isVisible = Preferences.showMenuBarIcon.value
    }

    /// A menu bar for when Pillbox is active (a Settings window is open), so ⌘, and ⌘Q work. The status item menu
    /// only handles its own key equivalents while it is open.
    private func setupMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Pillbox")
        let settingsItem = NSMenuItem(title: localized("Settings…"), action: #selector(settings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: localized("Quit Pillbox"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        // Without an Edit menu, ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z do nothing in the text fields of Settings. The actions go to the
        // first responder (nil target), so they reach whichever field has focus.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: localized("Edit"))
        for (title, action, key) in [(localized("Undo"), Selector(("undo:")), "z"), (localized("Redo"), Selector(("redo:")), "Z"),
                                     (localized("Cut"), #selector(NSText.cut(_:)), "x"), (localized("Copy"), #selector(NSText.copy(_:)), "c"),
                                     (localized("Paste"), #selector(NSText.paste(_:)), "v"), (localized("Select All"), #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Re-applies the settings that take effect at once. Runs on every settings change; each apply is safe to repeat.
    /// Not called at launch: it needs the status item, which is set up later in applicationDidFinishLaunching.
    private func applyDefaultsFeatures() {
        HyperKey.shared.apply(); ExtraBrightness.shared.apply(); WindowDrag.shared.apply(); if #available(macOS 14.2, *) { EqualizerService.shared.apply() }
        MenuBarHider.shared.apply(); MenuBarDetach.shared.apply(); MenuBarCalendar.shared.apply()
        AudioSpectrum.shared.apply(); DoubleTapKey.shared.apply(); DesktopWidgets.shared.apply()
        SettingsWindow.applyTheme(); applyStatusItemVisibility()
        applyHotKeys(); ActivityCounter.shared.apply(); PointerHider.shared.apply(); TypingSounds.shared.apply()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Pillbox")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu(menu)
        applyStatusItemVisibility()
    }

    /// Rebuilt every time the menu opens, so the checkmarks and the running timer are current.
    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        func icon(_ symbol: String) -> NSImage? {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            image?.isTemplate = true
            return image
        }
        func add(_ title: String, _ symbol: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = [.control, .option], target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: localized(title), action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.image = icon(symbol)
            item.target = target ?? self
            menu.addItem(item)
            return item
        }
        _ = add("Toggle Notch", "capsule.portrait.bottomhalf.filled", #selector(toggleNotch), key: GlobalShortcut.toggleNotch.key.lowercased())
        _ = add("Command Palette", "command", #selector(palette), key: GlobalShortcut.palette.key.lowercased())

        menu.addItem(.separator())
        let tabs = NSMenu()
        for tab in Tab.visible {
            let item = NSMenuItem(title: tab.title, action: #selector(openTab(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = tab.rawValue
            item.image = icon(tab.symbol)
            tabs.addItem(item)
        }
        let open = NSMenuItem(title: localized("Open Tab"), action: nil, keyEquivalent: "")
        open.image = icon("square.grid.2x2")
        open.submenu = tabs
        menu.addItem(open)
        let awake = add("Keep Awake", "cup.and.saucer.fill", #selector(toggleAwake), mods: [])
        awake.state = CaffeineService.shared.active ? .on : .off

        // Everything the palette does, so the features are reachable without knowing the shortcut.
        let actions = NSMenu()
        for command in PaletteModel().commands {
            let item = NSMenuItem(title: command.title, action: #selector(runAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ActionBox(command.run)
            actions.addItem(item)
        }
        let more = NSMenuItem(title: localized("Actions"), action: nil, keyEquivalent: "")
        more.image = icon("bolt")
        more.submenu = actions
        menu.addItem(more)

        // One click connects a paired device that is off.
        let bluetooth = NSMenu()
        for device in BluetoothConnect.pairedOffline() {
            let item = NSMenuItem(title: device.name, action: #selector(connectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            bluetooth.addItem(item)
        }
        if bluetooth.items.isEmpty { bluetooth.addItem(NSMenuItem(title: localized("No paired device to connect"), action: nil, keyEquivalent: "")) }
        let connect = NSMenuItem(title: localized("Connect a Bluetooth Device"), action: nil, keyEquivalent: "")
        connect.image = icon("airpodspro")
        connect.submenu = bluetooth
        menu.addItem(connect)

        menu.addItem(.separator())
        _ = add("Settings…", "gearshape", #selector(settings), key: ",", mods: .command)
        _ = add("Quit Pillbox", "power", #selector(NSApplication.terminate(_:)), key: "q", mods: .command, target: NSApp)
    }

    @objc private func toggleNotch() { NotchModel.shared.toggle() }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        // Clicking the status item activates Pillbox, and commands like snap or video speed act on the app in front.
        // Hand the focus back to the app the user was in first.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier, let app = lastOtherApp {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { box.run() } }
        } else {
            MainActor.assumeIsolated { box.run() }
        }
    }

    @objc private func connectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let name = BluetoothConnect.name(of: id) else { return }
        BluetoothConnect.connect(id) { ok in
            NotchModel.shared.show(Activity(symbol: ok ? "checkmark.circle" : "exclamationmark.triangle",
                                            title: ok ? localized("Connected to %@", name) : localized("Could not connect to %@", name),
                                            tint: ok ? .green : .orange, duration: 2.5))
        }
    }
    @objc private func palette() { PaletteController.shared.toggle() }
    @objc private func settings() { SettingsWindow.show() }
    @objc private func toggleAwake() { CaffeineService.shared.toggle() }
    @objc private func openTab(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tab = Tab(rawValue: raw) else { return }
        NotchModel.shared.expand(tab)
    }

}
