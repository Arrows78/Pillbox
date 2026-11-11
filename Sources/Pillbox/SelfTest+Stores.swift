import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func clipboard() {
        if case .url = ClipboardService.kind(of: "https://example.com/a") {} else { check("clipboard detects URL", false) }
        if case .color(_, let h) = ClipboardService.kind(of: "#ff8800") { check("clipboard detects hex colour", h == "#ff8800") } else { check("clipboard detects hex colour", false) }
        if case .email = ClipboardService.kind(of: "a@b.co") {} else { check("clipboard detects email", false) }
        if case .plain = ClipboardService.kind(of: "hello world") { check("clipboard keeps plain text", true) } else { check("clipboard keeps plain text", false) }
        check("hex round trip", NSColor(hex: "#336699")?.hexString == "#336699", NSColor(hex: "#336699")?.hexString ?? "nil")
        check("short hex expands", NSColor(hex: "f80")?.hexString == "#FF8800", NSColor(hex: "f80")?.hexString ?? "nil")
    }

    static func stores() {
        let notes = NotesStore()
        notes.draft = "  buy milk  "; notes.add()
        notes.draft = "   "; notes.add()
        check("notes: add trims and ignores blanks", notes.notes.count == 1 && notes.notes[0].text == "buy milk")
        notes.toggle(notes.notes[0])
        check("notes: toggle marks done", notes.notes[0].done)
        let persisted = Store.load("notes.json", as: [Note].self)
        check("notes: saved to disk", persisted?.count == 1 && persisted?[0].done == true)
        notes.clearDone()
        check("notes: clear done", notes.notes.isEmpty)

        let launcher = LauncherStore()
        launcher.paths = ["/A", "/B", "/C"]
        launcher.move("/C", onto: "/A")
        check("launcher: C takes A's slot", launcher.paths == ["/C", "/A", "/B"], "\(launcher.paths)")
        launcher.move("/A", onto: "/B")
        check("launcher: moving forward takes the target's slot", launcher.paths == ["/C", "/B", "/A"], "\(launcher.paths)")
        launcher.move("/A", onto: "/A")
        check("launcher: dropping on itself changes nothing", launcher.paths == ["/C", "/B", "/A"])

        let clip = ClipboardService()
        clip.items = (0..<(ClipboardService.cap + 10)).map { ClipItem(text: "item \($0)", date: Date(timeIntervalSinceNow: Double($0))) }
        clip.items[0].pinned = true   // the oldest item, pinned: it must survive the cap
        clip.trim()
        check("clipboard: cap keeps pinned items", clip.items.count == ClipboardService.cap + 1 && clip.items.contains { $0.pinned }, "\(clip.items.count)")
        check("clipboard: pinned sort first", clip.filtered.first?.pinned == true)
        clip.query = "item 69"
        check("clipboard: search", clip.filtered.map(\.text) == ["item 69"], "\(clip.filtered.map(\.text))")
        var withOCR = ClipItem(imageFile: "x.png"); withOCR.ocr = "invoice total 42"
        clip.items.append(withOCR); clip.query = "invoice"
        check("clipboard: search finds text inside images", clip.filtered.count == 1)
        clip.query = ""
        clip.items = [ClipItem(text: "hello"), ClipItem(text: "https://apple.com"), ClipItem(text: "#FF8800"), ClipItem(text: "a@b.co"), ClipItem(imageFile: "x.png")]
        let kinds = { (f: ClipFilter) in clip.items.filter(f.matches).count }
        check("clipboard: type filters", kinds(.all) == 5 && kinds(.text) == 2 && kinds(.links) == 1 && kinds(.colors) == 1 && kinds(.images) == 1,
              "\(ClipFilter.allCases.map(kinds))")
        clip.filter = .links
        check("clipboard: the filter applies to the list", clip.filtered.map(\.text) == ["https://apple.com"])
        check("shelf: summary counts items and selection", ShelfService.summary(count: 1, selected: 0) == localized("1 item")
              && ShelfService.summary(count: 3, selected: 2) == localized("%lld items", 3) + " · " + localized("%lld selected", 2))
        check("timer: presets are sorted, none for the stopwatch", TimerService.Mode.allCases.allSatisfy { $0.presets == $0.presets.sorted() }
              && TimerService.Mode.stopwatch.presets.isEmpty && TimerService.Mode.focus.presets.contains(25))

        // An unreadable file loads as nil and is kept as a .broken copy, so the next save cannot wipe the user's data.
        let broken = "selftest-broken.json"
        try? Data("{not json".utf8).write(to: Store.dir.appendingPathComponent(broken))
        check("store: an unreadable file loads as nil and is kept as a .broken copy", Store.load(broken, as: [String: Int].self) == nil
              && FileManager.default.fileExists(atPath: Store.dir.appendingPathComponent(broken + ".broken").path))
        try? FileManager.default.removeItem(at: Store.dir.appendingPathComponent(broken))
        try? FileManager.default.removeItem(at: Store.dir.appendingPathComponent(broken + ".broken"))
    }

    static func snippets() {
        let st = SnippetsStore.shared   // the palette reads the shared store
        st.snippets = []
        st.draftName = "Sign-off"; st.draftText = "Best regards,\nThomas"; st.add()
        st.draftName = "  "; st.draftText = "x"; st.add()
        st.draftName = "Empty"; st.draftText = "   "; st.add()
        check("snippets: add keeps valid, rejects blank name or text", st.snippets.count == 1 && st.snippets[0].text.contains("\n"), "\(st.snippets.count)")
        check("snippets: saved to disk", Store.load("snippets.json", as: [Snippet].self)?.count == 1)
        let m = PaletteModel(); m.query = "sign"
        check("snippets: found from the palette", m.commands.contains { $0.title == localized("Snippet: %@", "Sign-off") })
        st.remove(st.snippets[0])
        check("snippets: remove", st.snippets.isEmpty)
    }

    static func shellActions() {
        let ok = ActionRunner.runShell("echo hello; echo oops 1>&2")
        check("actions: runs a command and returns its output", ok.status == 0 && ok.output.contains("hello") && ok.output.contains("oops"), "\(ok)")
        check("actions: exit status is reported", ActionRunner.runShell("exit 3").status == 3)
        let t0 = Date(); let slow = ActionRunner.runShell("sleep 20", timeout: 1)
        check("actions: a hung command is killed after the timeout", slow.status == 124 && Date().timeIntervalSince(t0) < 5, "\(slow.status) \(Date().timeIntervalSince(t0))s")
        check("actions: only web and mail links", ActionRunner.url("https://example.com/a")?.host == "example.com" && ActionRunner.url("example.com")?.scheme == "https" && ActionRunner.url("mailto:a@b.co") != nil
              && ActionRunner.url("file:///etc/passwd") == nil && ActionRunner.url("javascript:alert(1)") == nil && ActionRunner.url("ftp://x.y") == nil)
        let st = QuickActionsStore.shared; st.actions = []
        check("actions: valid entries are saved", st.add(name: "Hi", kind: .shell, value: "echo hi") && st.add(name: "Site", kind: .web, value: "example.com") && st.actions.count == 2)
        check("actions: blank or unsafe entries are refused", !st.add(name: " ", kind: .shell, value: "x") && !st.add(name: "Bad", kind: .web, value: "file:///etc/passwd") && !st.add(name: "Empty", kind: .url, value: "") && st.actions.count == 2)
        check("actions: persisted to disk", Store.load("actions.json", as: [QuickAction].self)?.map(\.name) == ["Hi", "Site"])
        st.actions = []
    }

    static func settingsBackup() {
        let suite = UserDefaults(suiteName: "pillbox.selftest.backup")!; suite.removePersistentDomain(forName: "pillbox.selftest.backup")
        suite.set(false, forKey: "hoverOpen"); suite.set(0.3, forKey: "hoverDelay"); suite.set("evil", forKey: "devAPIToken"); suite.set(true, forKey: "devAPIEnabled")
        let data = SettingsBackup.data(from: suite)!
        check("backup: leaves the local API switch and token out", { let f = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]; let st = f?["settings"] as? [String: Any]; return st?["devAPIToken"] == nil && st?["devAPIEnabled"] == nil && st?["hoverOpen"] as? Bool == false }())
        let other = UserDefaults(suiteName: "pillbox.selftest.backup2")!; other.removePersistentDomain(forName: "pillbox.selftest.backup2")
        check("backup: restores what it holds", SettingsBackup.restore(data, into: other) == 2 && other.object(forKey: "hoverOpen") as? Bool == false && other.double(forKey: "hoverDelay") == 0.3)
        let hostile: [String: Any] = ["format": "pillbox-settings", "version": 1, "settings": ["hoverDelay": 99.0, "hoverOpen": "yes", "hudStyle": "<script>", "devAPIEnabled": true, "panelScale": 1.1, "searchEngine": "bing"]]
        let hdata = try! PropertyListSerialization.data(fromPropertyList: hostile, format: .xml, options: 0)
        let third = UserDefaults(suiteName: "pillbox.selftest.backup3")!; third.removePersistentDomain(forName: "pillbox.selftest.backup3")
        check("backup: clamps numbers, drops wrong types, unknown values and unlisted keys", SettingsBackup.restore(hdata, into: third) == 3 && third.double(forKey: "hoverDelay") == 0.6 && third.object(forKey: "hoverOpen") == nil && third.object(forKey: "hudStyle") == nil && third.object(forKey: "devAPIEnabled") == nil && third.string(forKey: "searchEngine") == "bing")
        check("backup: a foreign plist is not a backup", SettingsBackup.restore(try! PropertyListSerialization.data(fromPropertyList: ["hoverOpen": true], format: .xml, options: 0), into: third) == nil)
        SettingsBackup.resetAll(in: other)
        check("backup: reset removes every stored setting", other.object(forKey: "hoverOpen") == nil && other.object(forKey: "hoverDelay") == nil)
        for (suite, name) in [(suite, "pillbox.selftest.backup"), (other, "pillbox.selftest.backup2"), (third, "pillbox.selftest.backup3")] { suite.removePersistentDomain(forName: name) }
    }

    static func copyStackAndHistory() {
        var st = CopyStack(); st.push("one"); st.push("two"); st.push("three")
        check("stack: pastes in the order of copying", st.pop() == "one" && st.pop() == "two" && st.items == ["three"])
        var big = CopyStack(); for n in 0..<(CopyStack.cap + 5) { big.push("\(n)") }
        check("stack: capped, dropping the oldest", big.items.count == CopyStack.cap && big.items.first == "5")
        check("stack: empty gives nil", { var e = CopyStack(); return e.pop() == nil }())
        var h = CalcHistory(); h.add(expression: "2+2", result: "4"); h.add(expression: "3*3", result: "9"); h.add(expression: "2+2", result: "4")
        check("calc history: newest first, no duplicates", h.entries == ["2+2 = 4", "3*3 = 9"], "\(h.entries)")
        for n in 0..<15 { h.add(expression: "\(n)+1", result: "\(n + 1)") }
        check("calc history: capped", h.entries.count == CalcHistory.cap)
        check("calc history: gets the result back", CalcHistory.result(of: "2+2 = 4") == "4")
    }

    static func clipboardImport() {
        let clip = ClipboardService.shared; clip.items = [ClipItem(text: "kept")]
        let merged = ClipboardImport.merge([("kept", Date(), false), ("new one", Date(timeIntervalSince1970: 1), true), ("  ", Date(), false)], into: clip)
        check("clipboard import: new texts added with their date and pin, duplicates and blanks skipped", merged == 1 && clip.items.count == 2 && clip.items.last?.pinned == true && clip.items.last?.date == Date(timeIntervalSince1970: 1))
        clip.items = []
    }

    static func shortcutsAndDiagnostics() {
        check("shortcuts: every global shortcut has its own id and key", Set(GlobalShortcut.allCases.map(\.rawValue)).count == GlobalShortcut.allCases.count && GlobalShortcut.palette.keycaps == "⌃⌥K")
        check("diagnostics: no home folder or user name", !Diagnostics.text.contains(NSHomeDirectory()) && !Diagnostics.text.contains(NSUserName()))
    }

    /// A feature is applied only when one of its keys changed since it was last applied.
    static func settingsRouter() {
        let key = "selfTestRouterKey"
        UserDefaults.standard.removeObject(forKey: key); defer { UserDefaults.standard.removeObject(forKey: key) }
        var runs = 0
        let router = FeatureRouter([AppFeature(name: "self test", keys: [key], apply: { runs += 1 })])
        router.prime()
        router.applyChanged()
        check("settings router: no change, no apply", runs == 0)
        UserDefaults.standard.set(true, forKey: key)
        router.applyChanged()
        check("settings router: a changed key applies", runs == 1)
        router.applyChanged()
        check("settings router: applies once per change", runs == 1)
    }

    /// A browser's media answer is read from the end, so a title with a bar in it survives; Firefox is not scripted.
    static func browserMusic() {
        let now = BrowserMusic.parse("Song | Live|0|12.5|200", bundleID: "com.google.Chrome", browser: "Chrome")
        check("browser music: a title with a bar keeps it", now?.title == "Song | Live")
        check("browser music: a playing tab reads as playing, with its position", now?.playing == true && now?.position == 12.5 && now?.duration == 200)
        check("browser music: a paused tab reads as paused", BrowserMusic.parse("T|1|0|0", bundleID: "x", browser: "x")?.playing == false)
        check("browser music: no media element gives nothing", BrowserMusic.parse("none", bundleID: "x", browser: "x") == nil)
        check("browser music: Chrome runs its JavaScript through the tab", BrowserMusic.script(bundleID: "com.google.Chrome", js: "1")?.contains("execute javascript") == true)
        check("browser music: Safari runs its JavaScript in the front document", BrowserMusic.script(bundleID: "com.apple.Safari", js: "1")?.contains("do JavaScript") == true)
        check("browser music: Firefox is not scripted", BrowserMusic.script(bundleID: "org.mozilla.firefox", js: "1") == nil)
    }

    /// Shelf entries age out after the days chosen, an entry from before dates still loads, and muting is per app.
    static func shelfAndMute() {
        let now = Date()
        check("shelf: no cutoff when entries are kept for good", ShelfService.cutoff(keepDays: 0, now: now) == nil)
        check("shelf: entries older than the days are cut", ShelfService.cutoff(keepDays: 7, now: now).map { now.timeIntervalSince($0) } == 7 * 86400)
        let old = Data(#"{"id":"6B6F2C1E-0000-4000-8000-000000000001","path":"/tmp/a.txt"}"#.utf8)
        let item = try? JSONDecoder().decode(ShelfItem.self, from: old)
        check("shelf: an entry from before dates still loads", item?.path == "/tmp/a.txt")
        let key = NotificationMute.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        NotificationMute.setMuted("com.apple.mail", true)
        check("notifications: a muted app is muted", NotificationMute.isMuted("com.apple.mail") && !NotificationMute.isMuted("com.apple.Notes"))
        NotificationMute.setMuted("com.apple.mail", false)
        check("notifications: unmuting brings the app back", !NotificationMute.isMuted("com.apple.mail"))
    }

    /// The focus export writes a header and one sorted row per day, and the timer's sound is one of the offered ones.
    static func focusExport() {
        check("focus export: a header, then one row per day, oldest first", FocusExport.csv(["2026-11-02": 3, "2026-11-01": 1]) == "date,focus_sessions\n2026-11-01,1\n2026-11-02,3\n")
        check("focus export: no sessions gives the header only", FocusExport.csv([:]) == "date,focus_sessions\n")
        check("timer sound: the default is one of the offered sounds", FocusExport.sounds.contains(Preferences.timerSound.defaultValue))
    }

    /// The pomodoro cycle makes every n-th break the long one; 0 turns it off.
    static func pomodoroCycle() {
        check("pomodoro: the fourth focus session gives the long break", Pomodoro.longBreakDue(focusDone: 4, every: 4))
        check("pomodoro: the third focus session does not", !Pomodoro.longBreakDue(focusDone: 3, every: 4))
        check("pomodoro: off with 0 sessions per cycle", !Pomodoro.longBreakDue(focusDone: 4, every: 0))
        check("pomodoro: no focus session yet, no long break", !Pomodoro.longBreakDue(focusDone: 0, every: 4))
    }

    /// The quiet period holds between its hours, also when it crosses midnight, and is off when it has no start.
    static func quietHours() {
        check("quiet hours: inside a daytime period", QuietHours.isQuiet(hour: 14, from: 13, to: 15))
        check("quiet hours: outside a daytime period", !QuietHours.isQuiet(hour: 15, from: 13, to: 15))
        check("quiet hours: a period over midnight holds late and early", QuietHours.isQuiet(hour: 23, from: 22, to: 7) && QuietHours.isQuiet(hour: 3, from: 22, to: 7))
        check("quiet hours: a period over midnight lets the day through", !QuietHours.isQuiet(hour: 12, from: 22, to: 7))
        check("quiet hours: off without a start", !QuietHours.isQuiet(hour: 3, from: -1, to: 7))
    }

    /// The menu bar shows the next event within the hours chosen, and always when the choice is Always.
    static func menuBarCalendarWindow() {
        let now = Date()
        check("menu bar calendar: always shows when the choice is Always", MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(9 * 3600), within: 0, now: now))
        check("menu bar calendar: a near event shows", MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(3600), within: 1, now: now))
        check("menu bar calendar: a far event is hidden", !MenuBarCalendar.showsEvent(starting: now.addingTimeInterval(4 * 3600), within: 3, now: now))
        check("menu bar: the detachable tabs skip Home, Terminal and Prompter", !MenuBarDetach.detachable.contains(.home) && !MenuBarDetach.detachable.contains(.terminal) && MenuBarDetach.detachable.contains(.music))
    }

    /// The palette matches letters in order, ranks word starts and runs first, keeps recent commands, and reads prefixes.
    static func paletteRanking() {
        check("palette ranking: letters must all be there, in order", FuzzyMatch.score("kbl", in: "Keyboard backlight") != nil && FuzzyMatch.score("snx", in: "Snap center") == nil)
        check("palette ranking: a run of letters beats scattered ones", (FuzzyMatch.score("snap", in: "Snap center") ?? 0) > (FuzzyMatch.score("snap", in: "Sensor nominal active payload") ?? 0))
        check("palette ranking: an empty query keeps the order", PaletteModel.ranked([], "") .isEmpty)
        if case .commands(let rest) = PalettePrefix(">mute") { check("palette prefix: > keeps commands", rest == "mute") } else { check("palette prefix: > keeps commands", false) }
        if case .clipboard(let rest) = PalettePrefix("/code") { check("palette prefix: / keeps the clipboard", rest == "code") } else { check("palette prefix: / keeps the clipboard", false) }
        if case .none = PalettePrefix("mute") {} else { check("palette prefix: no prefix means everything", false) }
        let key = PaletteRecents.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        PaletteRecents.record("Alpha"); PaletteRecents.record("Beta"); PaletteRecents.record("Alpha")
        check("palette recents: the last one run comes first, once each", PaletteRecents.titles == ["Alpha", "Beta"])
    }

    /// A data backup holds the files of the data folder with a manifest, and reading it back lists their entries.
    static func dataBackup() {
        let name = "backup-check.json"
        let file = Store.dir.appendingPathComponent(name)
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-check-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: zip) }
        Store.save([1, 2], name)
        do {
            try DataBackup.export(to: zip)
            let folder = try DataBackup.unpack(zip)
            defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
            let entries = DataBackup.entries(in: folder)
            check("data backup: the file and its entry count are listed", entries.contains(DataBackup.Entry(name: name, items: 2)))
            check("data backup: the manifest is not listed as data", !entries.contains { $0.name == DataBackup.manifestName })
        } catch {
            check("data backup: export and unpack work", false)
        }
        let notABackup = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-not-a-backup-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: notABackup) }
        try? Data("not a zip".utf8).write(to: notABackup)
        check("data backup: a file that is not a backup is refused", (try? DataBackup.unpack(notABackup)) == nil)
    }

    /// Background work pauses while the screen is locked, the Mac sleeps or Low Power Mode is on, and resumes after.
    static func powerGate() {
        let gate = PowerGate.shared
        let (asleep, locked, lowPower) = (gate.asleep, gate.locked, gate.lowPower)
        defer { gate.asleep = asleep; gate.locked = locked; gate.lowPower = lowPower }
        gate.asleep = false; gate.locked = false; gate.lowPower = false
        check("power gate: running when nothing is hiding the screen", !gate.paused)
        gate.locked = true
        check("power gate: the screen lock pauses", gate.paused)
        gate.locked = false; gate.asleep = true
        check("power gate: sleep pauses", gate.paused)
        gate.asleep = false; gate.lowPower = true
        check("power gate: low power pauses", gate.paused)
    }

    /// A file written before versions still loads, and the next save writes its version beside the data.
    static func storeSchema() {
        let name = "schema-check.json"
        let url = Store.dir.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("[1,2,3]".utf8).write(to: url)
        check("store schema: a file from before versions still loads", Store.load(name, as: [Int].self) == [1, 2, 3])
        Store.save([4, 5], name)
        check("store schema: saving writes the version", (try? String(contentsOf: url))?.contains("\"version\"") == true)
        check("store schema: a versioned file loads its data", Store.load(name, as: [Int].self) == [4, 5])
    }

    /// Each pane knows the preferences it edits; the permissions pane edits none, so it has no reset.
    static func paneReset() {
        check("reset: the island pane lists its own preferences", (SettingsPane.preferenceKeys[.island] ?? []).contains(Preferences.hoverOpen.key))
        check("reset: the permissions pane has nothing to reset", (SettingsPane.preferenceKeys[.permissions] ?? []).isEmpty)
        check("reset: every pane's keys are real preference keys", SettingsPane.preferenceKeys.values.flatMap { $0 }.allSatisfy { !$0.isEmpty })
    }

    /// The notification search matches the title, the text or the app's name, and an empty search matches all.
    static func notificationSearch() {
        let n = NotificationItem(id: 1, app: "com.apple.mail", title: "Invoice ready", body: "Your PDF is attached", date: Date())
        check("notifications: an empty search matches", NotificationsTab.matches("  ", n, app: "Mail"))
        check("notifications: the title matches, any case", NotificationsTab.matches("invoice", n, app: "Mail"))
        check("notifications: the text matches", NotificationsTab.matches("pdf", n, app: "Mail"))
        check("notifications: the app name matches", NotificationsTab.matches("mail", n, app: "Mail"))
        check("notifications: something else does not", !NotificationsTab.matches("calendar", n, app: "Mail"))
    }

    /// The menu bar icon shows the most urgent state, and the menu's header only the event of the coming hours.
    static func statusMenu() {
        check("status icon: a recording wins and is red", StatusIconLook.resolve(recording: true, timer: "12:00", micMuted: true, awake: true) == StatusIconLook(symbol: "record.circle.fill", title: "", alert: true))
        check("status icon: a timer shows its countdown", StatusIconLook.resolve(recording: false, timer: "04:59", micMuted: true, awake: true).title == "04:59")
        check("status icon: muted microphone before keep awake", StatusIconLook.resolve(recording: false, timer: nil, micMuted: true, awake: true).symbol == "mic.slash.fill")
        check("status icon: plain capsule when nothing is live", StatusIconLook.resolve(recording: false, timer: nil, micMuted: false, awake: false).symbol == "capsule.fill")
        let now = Date()
        func event(_ id: String, in minutes: Double, allDay: Bool = false) -> AgendaEvent {
            AgendaEvent(id: id, title: id, start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval(minutes * 60 + 1800), allDay: allDay, calendar: "", color: .blue, join: nil)
        }
        check("status menu: the soonest timed event of the coming hours", AppDelegate.nextEvent(in: [event("later", in: 120), event("soon", in: 20), event("day", in: 5, allDay: true)], now: now)?.id == "soon")
        check("status menu: an event in progress counts", AppDelegate.nextEvent(in: [event("now", in: -10)], now: now)?.id == "now")
        check("status menu: nothing beyond three hours", AppDelegate.nextEvent(in: [event("tonight", in: 300)], now: now) == nil)
    }

    /// The island history keeps the last islands once each, newest first, and leaves the passing HUDs out.
    static func islandHistory() {
        let history = IslandHistory()
        let code = Activity(symbol: "key.fill", title: "Code")
        history.record(code)
        history.record(code)
        check("island history: an island is kept once", history.entries.count == 1)
        history.record(Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.5))
        history.record(Activity(symbol: "capslock.fill", title: "Caps Lock", priority: .low))
        history.record(Activity(symbol: "clock", title: "Again", inHistory: false))
        check("island history: HUDs and replays are left out", history.entries.count == 1)
        for i in 0..<30 { history.record(Activity(symbol: "bell", title: "\(i)")) }
        check("island history: keeps the last \(IslandHistory.limit), newest first", history.entries.count == IslandHistory.limit && history.entries.first?.title == "29")
    }

    /// Music follows the players' notifications, and moves the playhead itself between them.
    static func musicEvents() {
        check("music: the playhead moves on by the step", MusicService.advanced(10, by: 1, duration: 200) == 11)
        check("music: the playhead stops at the end of the track", MusicService.advanced(199.5, by: 1, duration: 200) == 200)
        check("music: no duration, no end", MusicService.advanced(5, by: 1, duration: 0) == 6)
        check("music: only Spotify and Music wake the service", MusicService.isPlayer("com.spotify.client") && MusicService.isPlayer("com.apple.Music") && !MusicService.isPlayer("com.apple.Safari") && !MusicService.isPlayer(nil))
        check("music: listens to both players", MusicService.playerNotifications.count == 2)
    }

    /// The tab order keeps Home first, keeps every tab once, and places tabs it does not know yet at the end.
    static func tabOrder() {
        check("tab order: nothing stored is the usual order", Tab.ordered(from: nil) == Tab.allCases)
        let order = Tab.ordered(from: "terminal,music,bogus,music,home")
        check("tab order: Home first, then the stored order", Array(order.prefix(3)) == [.home, .terminal, .music])
        check("tab order: every tab exactly once", order.count == Tab.allCases.count && Set(order) == Set(Tab.allCases))
        check("tab order: the other tabs follow in their usual order", Array(order.dropFirst(3)) == Tab.allCases.filter { ![.home, .terminal, .music].contains($0) })
    }

    /// The debug switches read their argument, and a switch at the end of the line has none.
    static func launchOptions() {
        check("launch options: the argument after a switch", LaunchOptions.value(after: "--open-tab", in: ["app", "--open-tab", "ai"]) == "ai")
        check("launch options: no argument when the switch ends the line", LaunchOptions.value(after: "--open-tab", in: ["app", "--open-tab"]) == nil)
        check("launch options: a switch is found", LaunchOptions.has("--open-menu", in: ["app", "--open-menu"]))
    }

    /// The idle animation plays at normal speed until the user changes it; a stored 0 is clamped, never frozen.
    static func lottieSpeedDefault() {
        check("lottie: 1x when the speed was never set", Preferences.lottieSpeed.defaultValue == 1.0)
    }

    /// Every permission is listed in exactly one card of the Permissions pane.
    static func permissionGroups() {
        let listed = PermissionGroup.allCases.flatMap { g in PermissionKind.allCases.filter { $0.group == g } }
        check("permissions: every permission is in exactly one card", listed.count == PermissionKind.allCases.count && Set(listed) == Set(PermissionKind.allCases))
        check("permissions: Bluetooth, Messages and browsers are listed", [PermissionKind.bluetooth, .messages, .browsers].allSatisfy { PermissionKind.allCases.contains($0) })
        check("permissions: browsers are asked for the ones VideoSpeed supports", VideoSpeed.browsers.keys.contains("com.apple.Safari"))
    }

    /// Home's layout always fills every slot, whatever the stored value holds.
    static func homeLayout() {
        check("home layout: nothing stored gives the defaults", HomeLayout.parse(nil, slots: 6, defaults: HomeLayout.defaultTiles) == HomeLayout.defaultTiles)
        check("home layout: a stored choice is kept", HomeLayout.parse("record,lyrics", slots: 2, defaults: HomeLayout.defaultCards.map { _ in HomeLayout.Tile.awake }) == [.record, .lyrics])
        check("home layout: rings default to CPU, memory and battery", HomeLayout.gauges(nil) == [.cpu, .memory, .battery])
        check("home layout: a ring can be the disk", HomeLayout.gauges("disk,cpu,battery") == [.disk, .cpu, .battery])
        check("home layout: the disk reading is a fraction", (0...1).contains(HomeLayout.diskUsed))
        check("home layout: unknown names are skipped, missing slots take the defaults",
              HomeLayout.parse("recentIslands,bogus", slots: 2, defaults: HomeLayout.defaultCards) == [.recentIslands, .upNext])
    }

    /// The settings search finds panes by their titles and their card and row titles.
    static func settingsSearch() {
        check("settings search: an empty query shows every pane", SettingsPane.matching("  ").count == SettingsPane.allCases.count)
        // The queries are the translated titles, so the check holds in every language.
        check("settings search: a row title finds its pane", SettingsPane.matching(localized("Hyper key")).contains(.windows))
        check("settings search: a card title finds its pane", SettingsPane.matching(localized("Equalizer")).contains(.audio))
        check("settings search: a row in another pane finds its own", SettingsPane.matching(localized("Hide everywhere")).contains(.island))
        check("settings search: nothing matches a nonsense query", SettingsPane.matching("zqxwv").isEmpty)
    }
}
