import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func geometry() {
        let m = NotchModel()
        m.geometry = NotchGeometry(width: 185, height: 32, screen: nil)
        check("collapsed pill is the notch size", m.size(hasWings: false) == CGSize(width: 185, height: 32))
        check("wings widen the pill", m.size(hasWings: true).width == 185 + NotchModel.wing * 2)
        m.expanded = true
        check("expanded size", m.size(hasWings: false) == NotchModel.expandedSize)
        m.tab = .terminal
        check("terminal tab opens at the same size as the others", m.size(hasWings: false) == NotchModel.expandedSize)
        var decided = ""
        m.requestApproval(tool: "Bash", detail: "ls", timeout: 60) { decided = $0 }
        check("approval takes over the island", m.size(hasWings: false).width == 520 && m.approval != nil)
        m.resolveApproval("allow")
        check("approval answers once and clears", decided == "allow" && m.approval == nil)
    }

    static func activityQueue() {
        func a(_ t: String, _ sym: String = "bell") -> Activity { Activity(symbol: sym, title: t) }
        var q = ActivityQueue()
        check("queue: the first island shows at once", q.push(a("A")) && q.current?.title == "A")
        check("queue: a different island waits its turn", !q.push(a("B")) && q.current?.title == "A" && q.pending.count == 1)
        var update = a("A"); update.progress = 0.7
        check("queue: an update of the visible island replaces it in place", q.push(update) && q.current?.progress == 0.7 && q.pending.count == 1)
        var upB = a("B"); upB.progress = 0.2
        _ = q.push(upB)
        check("queue: an update of a waiting island replaces it", q.pending.count == 1 && q.pending[0].progress == 0.2)
        for n in 0..<8 { _ = q.push(a("X\(n)")) }
        check("queue: the backlog is capped, keeping the newest", q.pending.count == ActivityQueue.cap && q.pending.last?.title == "X7", "\(q.pending.map(\.title))")
        let oldest = q.pending.first?.title; q.advance()
        check("queue: advancing shows the oldest waiting island", q.current?.title == oldest && q.pending.count == ActivityQueue.cap - 1, "\(String(describing: q.current?.title)) vs \(String(describing: oldest))")
        var e = ActivityQueue(); _ = e.push(a("Z")); e.advance()
        check("queue: advancing the last island empties it", e.current == nil)
        let m = NotchModel(); m.show(a("One")); m.show(a("Two"))
        check("model: a second island is queued, not shown over the first", m.activity?.title == "One")
        m.dismissActivity()
        check("model: dismissing shows the next one, then nothing", m.activity?.title == "Two")
        m.dismissActivity(); check("model: ... and then nothing", m.activity == nil)
    }

    static func tabsAndQueue() {
        check("tabs: hidden set parses, ignores unknown names and never hides Home",
              Tab.hidden(from: "music,home,bogus,terminal") == [.music, .terminal] && Tab.hidden(from: nil).isEmpty && Tab.hidden(from: "") .isEmpty)
        var q = ActivityQueue()
        _ = q.push(Activity(symbol: "speaker.wave.2.fill", title: "Volume", priority: .low))
        let shownHigh = q.push(Activity(symbol: "phone.fill", title: "In a call", priority: .high))
        let shownLow = q.push(Activity(symbol: "capslock", title: "Caps Lock on", priority: .low))
        _ = q.push(Activity(symbol: "bell", title: "Later")); _ = q.push(Activity(symbol: "battery.0", title: "Low battery", priority: .high))
        check("activity queue: high replaces a HUD and jumps the queue, low is dropped when busy",
              shownHigh && q.current?.title == "In a call" && !shownLow && q.pending.map(\.title) == ["Low battery", "Later"])
    }

    static func pillAndTheme() {
        check("pill: unknown or missing settings mean no action", { UserDefaults.standard.set("bogus", forKey: "doubleClickAction"); defer { UserDefaults.standard.removeObject(forKey: "doubleClickAction") }; return PillAction.configured("doubleClickAction") == .none && PillAction.configured("neverSet") == .none }())
        check("pill: every action has a distinct title", Set(PillAction.allCases.map(\.title)).count == PillAction.allCases.count)
        check("theme: four themes, black by default", IslandTheme.allCases.count == 4 && IslandTheme.current == .black)
    }

    static func usageAlert() {
        var st = UsageAlertState()
        check("usage alert: silent below the threshold", !st.shouldAlert(percent: 79, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: fires when the threshold is crossed", st.shouldAlert(percent: 81, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: only once per window", !st.shouldAlert(percent: 95, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: a new window can alert again, and so can another provider", st.shouldAlert(percent: 85, threshold: 80, windowKey: "Codex|2") && st.shouldAlert(percent: 85, threshold: 80, windowKey: "Other|2"))
    }

    static func edgeBar() {
        check("edge bar: fill follows the level and is clamped", EdgeHUD.fill(for: 0.5, trackHeight: 100) == 50 && EdgeHUD.fill(for: 2, trackHeight: 100) == 100 && EdgeHUD.fill(for: -1, trackHeight: 100) == 0)
        UserDefaults.standard.set("edge", forKey: "hudStyle"); defer { UserDefaults.standard.removeObject(forKey: "hudStyle") }
        let m = NotchModel(); m.show(Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.5))
        check("edge bar: with the edge style a volume change does not take over the island", m.activity == nil)
        m.show(Activity(symbol: "bell", title: "Hello"))
        check("edge bar: other islands still show", m.activity?.title == "Hello")
    }

    static func gesturesAndWorldClock() {
        // Gestures
        var d = DoubleTapDetector(); let t0 = Date()
        check("double tap: two quick presses", !d.press(at: t0) && d.press(at: t0.addingTimeInterval(0.2)))
        check("double tap: slow presses do not count, and it resets", !d.press(at: t0.addingTimeInterval(2)) && !d.press(at: t0.addingTimeInterval(3)))
        let first = CGPoint(x: SnapZones.margin + 5, y: SnapZones.margin + 5)
        check("snap zones: tile hit testing", SnapZones.zone(at: first) == .left && SnapZones.zone(at: CGPoint(x: 1, y: 1)) == nil
              && SnapZones.zone(at: CGPoint(x: SnapZones.margin + CGFloat(SnapZones.zones.firstIndex(of: .full)!) * (SnapZones.tile.width + SnapZones.gap) + 5, y: SnapZones.margin + 5)) == .full)
        let noon = Date(timeIntervalSince1970: 1_794_052_800)   // 2026-11-07 12:00 UTC
        check("world clock: each zone shows its own time", DesktopWidgetView.time(noon, zone: "Asia/Tokyo") == "21:00" && DesktopWidgetView.time(noon, zone: "America/New_York") == "07:00" && DesktopWidgetView.time(noon, zone: "Europe/London") == "12:00",
              "\(DesktopWidgetView.time(noon, zone: "Asia/Tokyo")) \(DesktopWidgetView.time(noon, zone: "America/New_York"))")
        check("mascot: the plant grows with progress", Mascot.emoji(for: .plant, progress: 0.1) == "🌱" && Mascot.emoji(for: .plant, progress: 0.5) == "🌿" && Mascot.emoji(for: .plant, progress: 0.9) == "🌳" && Mascot.emoji(for: .none, progress: 0.5) == nil)
    }

    static func shakeAndBreaks() {
        // Shake to open the shelf
        var shake = ShakeDetector(); var t = Date(); var fired = false
        for x in stride(from: 0.0, through: 300.0, by: 20.0) { t += 0.02; if shake.add(CGPoint(x: x, y: 0), at: t) { fired = true } }   // a straight drag
        check("shake: a straight drag is not a shake", !fired)
        shake.reset(); t = Date()
        let zig: [Double] = [0, 70, 0, 70, 0, 70, 0, 70]
        for target in zig { for step in 1...7 { t += 0.02; if shake.add(CGPoint(x: target == 70 ? Double(step) * 10 : 70 - Double(step) * 10, y: 0), at: t) { fired = true } } }
        check("shake: back-and-forth opens the shelf", fired)
        shake.reset(); t = Date(); fired = false
        for target in zig { for step in 1...7 { t += 0.4; if shake.add(CGPoint(x: target == 70 ? Double(step) * 10 : 70 - Double(step) * 10, y: 0), at: t) { fired = true } } }
        check("shake: a slow wander is not a shake", !fired)

        // Break reminders
        var b = BreakLogic(); let start = Date(); var fires = 0
        for m in 0...50 { if b.tick(idle: 2, now: start.addingTimeInterval(Double(m) * 60), every: 20 * 60) { fires += 1 } }
        check("break: reminds every 20 minutes of activity", fires == 2, "\(fires)")
        var c = BreakLogic(); var cf = 0
        for m in 0...50 { if c.tick(idle: m == 15 ? 90 : 2, now: start.addingTimeInterval(Double(m) * 60), every: 20 * 60) { cf += 1 } }
        check("break: an idle minute counts as a break", cf == 1, "\(cf)")
    }

    static func awareness() {
        let now = Date(), apps: Set<String> = ["com.hnc.Discord"]
        check("focus guard: blocks a listed app only while a Focus timer runs",
              FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: false, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .rest, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .stopwatch, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.apple.Safari", blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: nil, blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now))
        check("focus guard: Allow 5 min lets it through until the allowance ends",
              !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: ["com.hnc.Discord": now.addingTimeInterval(60)], now: now)
              && FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: ["com.hnc.Discord": now.addingTimeInterval(-1)], now: now))
        let fs: [String: Any] = ["ManagedSpaceID": 40, "type": 4, "TileLayoutManager": ["TileSpaces": [["appName": "Safari"]]]]
        let displays: [[String: Any]] = [["Spaces": [["ManagedSpaceID": 1, "type": 0], fs, ["ManagedSpaceID": 7, "type": 0], ["ManagedSpaceID": 41, "type": 4]]],
                                         ["Spaces": [["ManagedSpaceID": 90, "type": 0], ["ManagedSpaceID": 91, "type": 0]]]]
        check("spaces: desktops are numbered per display, skipping full-screen spaces",
              SpaceInfo.kind(displays: displays, active: 7) == .desktop(2) && SpaceInfo.kind(displays: displays, active: 1) == .desktop(1) && SpaceInfo.kind(displays: displays, active: 91) == .desktop(2))
        check("spaces: a full-screen space is named after its app, unknown ids give nothing",
              SpaceInfo.kind(displays: displays, active: 40) == .fullScreen("Safari") && SpaceInfo.kind(displays: displays, active: 41) == .fullScreen(nil) && SpaceInfo.kind(displays: displays, active: 5) == nil && SpaceInfo.kind(displays: [], active: 1) == nil)
        check("spaces: labels", SpaceInfo.label(.desktop(3), frontApp: "X") == localized("Desktop %d", 3) && SpaceInfo.label(.fullScreen(nil), frontApp: "Keynote") == "Keynote"
              && SpaceInfo.label(.fullScreen("Safari"), frontApp: "Keynote") == "Safari" && SpaceInfo.label(.fullScreen(nil), frontApp: nil) == localized("Full screen"))
        check("camera guard: never for Pillbox's own mirror", CameraGuard.island(mirrorOpen: true, frontName: "Zoom", frontBundle: "us.zoom.xos", own: "dev.labs.pillbox") == .hidden)
        check("camera guard: names the front app, but not Pillbox itself",
              CameraGuard.island(mirrorOpen: false, frontName: "Zoom", frontBundle: "us.zoom.xos", own: "dev.labs.pillbox") == .shown(probableApp: "Zoom")
              && CameraGuard.island(mirrorOpen: false, frontName: "Pillbox", frontBundle: "dev.labs.pillbox", own: "dev.labs.pillbox") == .shown(probableApp: nil))
        check("camera guard: an unknown front app is not named", CameraGuard.island(mirrorOpen: false, frontName: nil, frontBundle: "us.zoom.xos", own: "dev.labs.pillbox") == .shown(probableApp: nil))
        // App icons for the islands: no icon gives no picture, and the picture has the side asked for.
        let icon = AppIconImage.bitmap(NSImage(size: NSSize(width: 64, height: 64)), side: 16)
        check("app icon: none gives none, and the bitmap has the requested side", AppIconImage.bitmap(nil) == nil && icon?.representations.contains { $0.pixelsWide == 16 && $0.pixelsHigh == 16 } == true
              && AppIconImage.bitmap(NSImage(size: NSSize(width: 64, height: 64)))?.representations.contains { $0.pixelsWide == 48 } == true)
    }

    static func dictationAndActivity() {
        var t = DictationText(); t.update("hello", finished: false); t.update("hello world", finished: true); t.update("again", finished: false)
        check("dictation: text survives the recogniser's restarts", t.full == "hello world again", t.full)
        t.update("", finished: true)
        check("dictation: a request ending in an error keeps what it heard", t.full == "hello world again" && t.partial.isEmpty, t.full)
        check("dictation: nothing heard is empty", DictationText().full.isEmpty)
        check("dictation: level meter stays in range", SpeechListener.level(UnsafeBufferPointer(start: nil, count: 0)) == 0
              && [Float](repeating: 1, count: 64).withUnsafeBufferPointer { SpeechListener.level($0) } == 1
              && [Float](repeating: 0.001, count: 64).withUnsafeBufferPointer { SpeechListener.level($0) } < 0.5)
        check("dictation: its shortcut is opt-in", GlobalShortcut.dictate.setting == "dictationShortcut" && GlobalShortcut.palette.isEnabled && GlobalShortcut.dictate.keycaps == "⌃⌥D")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = { (d: Int, h: Int) in cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }
        var log = ActivityLog()
        log.add(keys: 10, clicks: 2, metres: 1.5, on: day(1, 23), calendar: cal)
        log.add(keys: 5, clicks: 1, metres: 0.5, on: day(1, 23), calendar: cal)
        log.add(keys: 7, clicks: 0, metres: 0, on: day(2, 0), calendar: cal)
        check("activity: counts add up within a day and roll over at midnight", log.days.count == 2 && log.days[0] == ActivityDay(day: "2026-03-01", keys: 15, clicks: 3, metres: 2) && log.days[1].keys == 7, "\(log.days)")
        for d in 3...12 { log.add(keys: d, clicks: 0, metres: 0, on: day(d, 12), calendar: cal) }
        check("activity: only the last 7 days are kept, oldest first", log.days.map(\.day) == (6...12).map { String(format: "2026-03-%02d", $0) }, "\(log.days.map(\.day))")
        let week = log.lastWeek(ending: day(14, 9), calendar: cal)
        check("activity: the week fills days without activity with zeros", week.count == 7 && week.first?.day == "2026-03-08" && week.last == ActivityDay(day: "2026-03-14") && week[4].keys == 12, "\(week)")
        check("activity: today's counts", log.today(day(12, 18), calendar: cal).keys == 12 && log.today(day(20, 1), calendar: cal).keys == 0)
        check("activity: the week crosses month ends", ActivityLog.week(ending: day(2, 8), calendar: cal).first == "2026-02-24")
        let mm = ActivityCounter.millimetresPerPoint(physicalWidth: 300, pointWidth: 1500)
        check("activity: points become millimetres from the screen's physical size", abs(mm - 0.2) < 1e-9 && ActivityCounter.millimetresPerPoint(physicalWidth: 0, pointWidth: 1500) == ActivityCounter.fallbackMillimetresPerPoint)
        check("activity: 500 points at 0.2 mm/pt is 10 cm", abs(ActivityCounter.metres(from: .zero, to: CGPoint(x: 3000, y: 4000).applying(.init(scaleX: 0.1, y: 0.1)), mmPerPoint: 0.2) - 0.1) < 1e-9)
        check("activity: a warp between screens is not travel", ActivityCounter.metres(from: .zero, to: CGPoint(x: 5000, y: 0), mmPerPoint: 0.2) == 0)
        let back = try? JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(log))
        check("activity: the log round-trips through JSON", back == log)
    }

    static func panelSize() {
        UserDefaults.standard.set(1.3, forKey: "panelScale"); defer { UserDefaults.standard.removeObject(forKey: "panelScale") }
        let m = NotchModel(); m.expanded = true
        check("panel: scales the open size", abs(m.size(hasWings: false).width - NotchModel.expandedSize.width * 1.3) < 0.01)
        UserDefaults.standard.set(9.0, forKey: "panelScale")
        check("panel: the scale is clamped", NotchModel.scale == 1.3)
        UserDefaults.standard.set(0.1, forKey: "panelScale")
        check("panel: ... on both sides", NotchModel.scale == 0.8)
        check("panel: the largest size of any tab fits its window at the largest scale", PanelSize.allCases.allSatisfy { $0.size.width * 1.3 <= NotchModel.windowSize.width && $0.size.height * 1.3 <= NotchModel.windowSize.height })
    }

    static func idleCollapse() {
        check("idle collapse: only an open, unpinned panel past the limit", IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 31, limit: 30)
              && !IdleCollapse.shouldCollapse(expanded: true, pinned: true, idle: 31, limit: 30) && !IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 31, limit: 0)
              && !IdleCollapse.shouldCollapse(expanded: false, pinned: false, idle: 31, limit: 30) && !IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 10, limit: 30))
    }
}
