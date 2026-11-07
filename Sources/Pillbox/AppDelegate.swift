import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var monitors: [Any] = []

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
        if PermissionsCenter.shared.state(of: .calendar) == .granted { CalendarService.shared.start() }
        DownloadsWatcher.shared.start()
        ScreenshotWatcher.shared.start()
        DriveWatcher.shared.start()
        Tools.startCapsLockHUD()
        KeystrokeHUD.shared.start()
        BrightnessHUD.shared.start()
        BreakReminder.shared.start()
        DownloadProgress.shared.start()
        BuildWatcher.shared.start()
        FocusMonitor.shared.start()
        CallMonitor.shared.start()
        HyperKey.shared.apply()
        MenuBarHider.shared.apply()
        MenuBarDetach.shared.apply()
        MenuBarCalendar.shared.apply()
        AudioSpectrum.shared.apply()
        DoubleTapKey.shared.apply()
        DesktopWidgets.shared.apply()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                HyperKey.shared.apply(); MenuBarHider.shared.apply(); MenuBarDetach.shared.apply(); MenuBarCalendar.shared.apply()
                AudioSpectrum.shared.apply(); DoubleTapKey.shared.apply(); DesktopWidgets.shared.apply()
            }
        }
        DevAPI.shared.apply()
        PrivacyService.shared.start()
        if PermissionsCenter.shared.state(of: .location) == .granted { WeatherService.shared.start() }
        StocksService.shared.start()
        AIUsageService.shared.start()
        RemindersService.shared.start()
        AudioControl.shared.startVolumeHUD()
        setupStatusItem()
        if CommandLine.arguments.contains("--open-teleprompter") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Teleprompter.shared.show() } }
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
        setupHover()
        setupDragToShelf()
        hotKeys = [
            HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey), id: 1) { PaletteController.shared.toggle() },
            HotKey(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), id: 2) { NotchModel.shared.toggle() },
        ]
        // ⌘1–9 switches tabs while the notch is open.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard NotchModel.shared.expanded, e.modifierFlags.contains(.command),
                  let c = e.charactersIgnoringModifiers, let n = Int(c), (1...Tab.allCases.count).contains(n) else { return e }
            NotchModel.shared.tab = Tab.allCases[n - 1]; return nil
        } as Any)
        // Swipe left/right on the notch to change tab.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, NotchModel.shared.expanded, abs(e.scrollingDeltaX) > 8, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 2,
                  e.phase == .began || e.phase == .changed, self.swipeCooldown < Date() else { return e }
            self.swipeCooldown = Date().addingTimeInterval(0.4)
            let tabs = Tab.allCases, i = tabs.firstIndex(of: NotchModel.shared.tab)!
            let j = e.scrollingDeltaX < 0 ? min(i + 1, tabs.count - 1) : max(i - 1, 0)
            NotchModel.shared.tab = tabs[j]; return e
        } as Any)
    }

    private var swipeCooldown = Date.distantPast
    private var sigterm: DispatchSourceSignal?

    /// Caps Lock must never stay remapped after Pillbox quits.
    func applicationWillTerminate(_ notification: Notification) { HyperKey.shared.disable(); AudioSpectrum.shared.stop() }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Pillbox")
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Notch", action: #selector(toggleNotch), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Command Palette", action: #selector(palette), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pillbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleNotch() { NotchModel.shared.toggle() }
    @objc private func palette() { PaletteController.shared.toggle() }
    @objc private func settings() { SettingsWindow.show() }

    // MARK: Hover open / auto close

    private func setupHover() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in self?.mouseMoved() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { e in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(e) } }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { e in handler(e); return e } as Any)
    }

    private func mouseMoved() {
        let model = NotchModel.shared
        let p = NSEvent.mouseLocation
        let rect = controller.shapeRectOnScreen
        if !model.expanded {
            leaveTask?.cancel()
            // The strip includes the screen edge so a flick to the top still counts.
            let hot = rect.insetBy(dx: -4, dy: 0).union(NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 3))
            if UserDefaults.standard.object(forKey: "hoverOpen") as? Bool ?? true, hot.contains(p) {
                guard hoverTask == nil else { return }
                let delay = UserDefaults.standard.double(forKey: "hoverDelay").nonZero ?? 0.12
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    defer { self?.hoverTask = nil }
                    guard !Task.isCancelled, let self, self.controller.shapeRectOnScreen.insetBy(dx: -4, dy: 0).contains(NSEvent.mouseLocation) || NSEvent.mouseLocation.y >= rect.maxY - 1 && (rect.minX...rect.maxX).contains(NSEvent.mouseLocation.x) else { return }
                    let peek = UserDefaults.standard.bool(forKey: "peekOnHover") && MusicService.shared.isPlaying
                    model.expand(peek ? .music : nil)
                }
            } else { hoverTask?.cancel(); hoverTask = nil }
        } else {
            hoverTask?.cancel(); hoverTask = nil
            if rect.insetBy(dx: -24, dy: -24).contains(p) || model.pinnedOpen { leaveTask?.cancel(); leaveTask = nil }
            else if leaveTask == nil {
                leaveTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    defer { self?.leaveTask = nil }
                    guard !Task.isCancelled, let self, !model.pinnedOpen,
                          !self.controller.shapeRectOnScreen.insetBy(dx: -24, dy: -24).contains(NSEvent.mouseLocation) else { return }
                    model.collapse()
                }
            }
        }
    }

    private var dragPasteboardCount = 0
    private var shake = ShakeDetector()

    /// A real drag-and-drop session changes the drag pasteboard; dragging a window does not (its contents are stale).
    private var isDataDrag: Bool { NSPasteboard(name: .drag).changeCount != dragPasteboardCount }

    /// Dragging a file toward the notch opens the shelf; dragging a window toward it shows snap zones.
    private func setupDragToShelf() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.dragPasteboardCount = NSPasteboard(name: .drag).changeCount; self.shake.reset() } }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let model = NotchModel.shared, p = NSEvent.mouseLocation
                    if self.isDataDrag {
                        guard !model.expanded else { return }
                        let pb = NSPasteboard(name: .drag)
                        guard pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
                        let shaken = UserDefaults.standard.object(forKey: "shakeToOpen") as? Bool ?? true && self.shake.add(p, at: Date())
                        if shaken || self.controller.shapeRectOnScreen.insetBy(dx: -30, dy: -30).contains(p) { model.pinnedOpen = true; model.expand(.shelf) }
                    } else if UserDefaults.standard.bool(forKey: "snapZones"), !model.expanded {
                        let r = self.controller.shapeRectOnScreen
                        if SnapZones.shared.visible { SnapZones.shared.update(mouse: p) }
                        else if p.y >= r.maxY - 36, abs(p.x - r.midX) < 260 { SnapZones.shared.show() }
                        if SnapZones.shared.visible, p.y < r.maxY - 220 { _ = SnapZones.shared.finish() }
                    }
                }
            }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if SnapZones.shared.visible, let zone = SnapZones.shared.finish() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { WindowSnap.snap(zone) } }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { NotchModel.shared.pinnedOpen = false } }
        } as Any)
    }
}
