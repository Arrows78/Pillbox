import AppKit

/// The sections of the menu bar menu that change with what is going on: the live header, the switches and the
/// grouped actions. AppDelegate assembles them with the fixed items.
extension AppDelegate {
    static func menuIcon(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        return image
    }

    /// A menu item that runs `run` where it is, without handing the focus back to another app first.
    func menuItem(_ title: String, _ symbol: String?, indent: Bool = false, run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runInPlace(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(run)
        item.image = symbol.flatMap(Self.menuIcon)
        item.indentationLevel = indent ? 1 : 0
        return item
    }

    /// A line that only says something, greyed out.
    static func menuLabel(_ title: String, _ symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = menuIcon(symbol)
        item.isEnabled = false
        return item
    }

    @objc func runInPlace(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        MainActor.assumeIsolated { box.run() }
    }

    /// What is going on now, each with its controls: the track, the timer and the next event of the coming hours.
    /// Empty when nothing is live, so the menu then starts with the usual items.
    func liveMenuItems(now: Date = Date()) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let music = MusicService.shared
        if music.hasTrack {
            let line = music.artist.isEmpty ? music.title : "\(music.title) — \(music.artist)"
            items.append(Self.menuLabel(String(line.prefix(60)), music.isPlaying ? "music.note" : "pause.circle"))
            items.append(menuItem(localized("Previous track"), "backward.fill", indent: true) { MusicService.shared.previous() })
            items.append(menuItem(localized(music.isPlaying ? "Pause" : "Play"), music.isPlaying ? "pause.fill" : "play.fill", indent: true) { MusicService.shared.playPause() })
            items.append(menuItem(localized("Next track"), "forward.fill", indent: true) { MusicService.shared.next() })
        }
        let timers = TimerService.shared
        if timers.isActive {
            let label = timers.label.isEmpty ? localized(timers.mode.rawValue) : timers.label
            items.append(Self.menuLabel("\(label) · \(timers.display)", "timer"))
            items.append(menuItem(localized(timers.running ? "Pause" : "Resume"), timers.running ? "pause.fill" : "play.fill", indent: true) { TimerService.shared.toggle() })
            items.append(menuItem(localized("Stop"), "stop.fill", indent: true) { TimerService.shared.reset() })
        }
        if let event = Self.nextEvent(in: AgendaModel.shared.events, now: now) {
            let time = event.start <= now ? localized("Now") : event.start.formatted(date: .omitted, time: .shortened)
            items.append(Self.menuLabel("\(time) · \(String(event.title.prefix(50)))", "calendar"))
            if let url = event.join { items.append(menuItem(localized("Join"), "video.fill", indent: true) { NSWorkspace.shared.open(url) }) }
        }
        return items
    }

    /// The timed event in progress or starting within the next `hours`, the soonest first.
    nonisolated static func nextEvent(in events: [AgendaEvent], now: Date, hours: Double = 3) -> AgendaEvent? {
        events.filter { !$0.allDay && $0.end > now && $0.start <= now.addingTimeInterval(hours * 3600) }.min { $0.start < $1.start }
    }

    /// The switches people flip often, with a checkmark that shows their state.
    func toggleMenuItems() -> [NSMenuItem] {
        func toggle(_ title: String, _ symbol: String, on: Bool, run: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = menuItem(localized(title), symbol, run: run)
            item.state = on ? .on : .off
            return item
        }
        func flip(_ key: String, default value: Bool) { UserDefaults.standard.set(!Defaults.bool(key, default: value), forKey: key) }
        return [
            toggle("Keep Awake", "cup.and.saucer.fill", on: CaffeineService.shared.active) { CaffeineService.shared.toggle() },
            toggle("Mute microphone", "mic.slash.fill", on: AudioControl.shared.micMuted) { AudioControl.shared.toggleMic() },
            toggle("Camera mirror", "video.fill", on: CameraMirror.shared.isOpen) { CameraMirror.shared.toggle() },
            toggle("Hide from screenshots and screen sharing", "eye.slash", on: Preferences.hideFromCapture.value) {
                flip(Preferences.hideFromCapture.key, default: Preferences.hideFromCapture.defaultValue)
            },
            toggle("Block distracting apps during focus", "hand.raised.fill", on: Preferences.focusBlocking.value) {
                flip(Preferences.focusBlocking.key, default: Preferences.focusBlocking.defaultValue)
            },
        ]
    }

    /// The last five things copied. Clicking one copies it again, ready to paste where the cursor is.
    func recentClipboardItem() -> NSMenuItem {
        let sub = NSMenu()
        let items = ClipboardService.shared.items.prefix(5)
        for item in items {
            let text = item.text.map { String($0.replacingOccurrences(of: "\n", with: " ").prefix(60)) } ?? localized("Image")
            sub.addItem(menuItem(text, item.text == nil ? "photo" : "doc.text") { ClipboardService.shared.copy(item) })
        }
        if items.isEmpty { sub.addItem(NSMenuItem(title: localized("Nothing copied yet"), action: nil, keyEquivalent: "")) }
        let entry = NSMenuItem(title: localized("Recent clipboard"), action: nil, keyEquivalent: "")
        entry.image = Self.menuIcon("doc.on.clipboard")
        entry.submenu = sub
        return entry
    }

    /// The latest islands, newest first. Clicking one shows it again.
    func recentIslandsItem() -> NSMenuItem {
        let sub = NSMenu()
        let entries = IslandHistory.shared.entries
        for entry in entries {
            let time = entry.date.formatted(date: .omitted, time: .shortened)
            sub.addItem(menuItem("\(time) · \(String(entry.title.prefix(60)))", entry.symbol) {
                NotchModel.shared.show(Activity(symbol: entry.symbol, title: entry.title, subtitle: entry.subtitle, duration: 4, inHistory: false))
            })
        }
        if entries.isEmpty {
            sub.addItem(NSMenuItem(title: localized("No island yet"), action: nil, keyEquivalent: ""))
        } else {
            sub.addItem(.separator())
            sub.addItem(menuItem(localized("Clear"), "trash") { IslandHistory.shared.clear() })
        }
        let item = NSMenuItem(title: localized("Recent islands"), action: nil, keyEquivalent: "")
        item.image = Self.menuIcon("clock.arrow.circlepath")
        item.submenu = sub
        return item
    }

    /// Everything the palette does, one submenu per category, so the features are reachable without the shortcut.
    func actionsMenu(_ commands: [PaletteCommand]) -> NSMenu {
        let menu = NSMenu()
        for category in PaletteCategory.allCases where category != .tabs {
            let inCategory = commands.filter { $0.category == category }
            guard !inCategory.isEmpty else { continue }
            let sub = NSMenu()
            for command in inCategory {
                let item = NSMenuItem(title: command.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ActionBox(command.run)
                item.image = Self.menuIcon(command.symbol)
                sub.addItem(item)
            }
            let group = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            group.submenu = sub
            menu.addItem(group)
        }
        return menu
    }
}
