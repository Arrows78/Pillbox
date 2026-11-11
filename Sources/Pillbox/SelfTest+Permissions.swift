import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func snapping() {
        let r = CGRect(x: 0, y: 0, width: 1200, height: 800)
        check("snap left half", SnapZone.left.frame(in: r) == CGRect(x: 0, y: 0, width: 600, height: 800))
        check("snap right half", SnapZone.right.frame(in: r) == CGRect(x: 600, y: 0, width: 600, height: 800))
        check("snap right third", SnapZone.rightThird.frame(in: r) == CGRect(x: 800, y: 0, width: 400, height: 800))
        check("snap full", SnapZone.full.frame(in: r) == r)
        check("snap top half", SnapZone.top.frame(in: r) == CGRect(x: 0, y: 0, width: 1200, height: 400))
        check("snap bottom half", SnapZone.bottom.frame(in: r) == CGRect(x: 0, y: 400, width: 1200, height: 400))
        check("snap left third", SnapZone.leftThird.frame(in: r) == CGRect(x: 0, y: 0, width: 400, height: 800))
        let c = SnapZone.center.frame(in: r)
        check("snap center: 70 % by 80 %, centred on the visible frame",
              abs(c.minX - 180) < 1e-6 && abs(c.minY - 80) < 1e-6 && abs(c.width - 840) < 1e-6 && abs(c.height - 640) < 1e-6, "\(c)")
        // Every zone follows the visible frame's origin, and stays inside it.
        let r2 = CGRect(x: 100, y: 50, width: 1200, height: 800)
        let inside = SnapZone.allCases.allSatisfy { r2.insetBy(dx: -1e-6, dy: -1e-6).contains($0.frame(in: r2)) }
        check("snap zones: all eight zones stay inside a visible frame that is not at the origin",
              SnapZone.allCases.count == 8 && inside && SnapZone.top.frame(in: r2) == CGRect(x: 100, y: 50, width: 1200, height: 400)
              && SnapZone.leftThird.frame(in: r2) == CGRect(x: 100, y: 50, width: 400, height: 800), "\(SnapZone.allCases.map { $0.frame(in: r2) })")
    }

    static func hyperKeyAndMenuBar() {
        // Hyper key
        let f = HyperKey.apply(to: [.maskShift])
        check("hyper: adds the four modifiers and keeps existing ones", f.contains([.maskControl, .maskAlternate, .maskShift, .maskCommand]))
        let json = HyperKey.mappingJSON(enabled: true).replacingOccurrences(of: "0x700000039", with: "30064771129").replacingOccurrences(of: "0x70000006D", with: "30064771181")
        let map = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any])?["UserKeyMapping"] as? [[String: Int]]
        check("hyper: Caps Lock maps to F18", map?.first?["HIDKeyboardModifierMappingSrc"] == 0x700000039 && map?.first?["HIDKeyboardModifierMappingDst"] == 0x70000006D, "\(String(describing: map))")
        check("hyper: disabling clears the mapping", HyperKey.mappingJSON(enabled: false) == "{\"UserKeyMapping\":[]}")

        // Menu bar
        check("menu bar: collapsing pushes icons away", MenuBarHider.separatorLength(collapsed: true) > 5_000 && MenuBarHider.separatorLength(collapsed: false) < 20)
        let now = Date()
        check("menu bar calendar: ongoing", MenuBarCalendar.label(title: "Standup", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600), now: now) == localized("%@ · now", "Standup"))
        check("menu bar calendar: soon", MenuBarCalendar.label(title: "Standup", start: now.addingTimeInterval(12 * 60 - 5), end: now.addingTimeInterval(3600), now: now) == localized("%@ · in %d min", "Standup", 12))
        check("menu bar calendar: long titles are cut", MenuBarCalendar.label(title: String(repeating: "x", count: 40), start: now.addingTimeInterval(300), end: now.addingTimeInterval(900), now: now).count < 40)
        check("menu bar: every tab that fits a popover can be detached", MenuBarDetach.detachable.count == Tab.allCases.count - 3 && !MenuBarDetach.detachable.contains(.terminal))
    }

    static func focusCallsAndNotifications() {
        // Focus
        let focus = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        check("focus: mode name from the assertions file", FocusMonitor.parse(Data(focus.utf8)) == "Work")
        let dnd = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}"#
        check("focus: Do Not Disturb", FocusMonitor.parse(Data(dnd.utf8)) == localized("Do Not Disturb"))
        check("focus: no record means no focus", FocusMonitor.parse(Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)) == nil && FocusMonitor.parse(Data("junk".utf8)) == nil)
        let sleep = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.sleep"}}]}]}"#
        let dndLegacy = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb"}}]}]}"#
        let skipsEmpty = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{}},{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        check("focus: a named mode is capitalised, the legacy DND id is Do Not Disturb, a record without a mode is skipped",
              FocusMonitor.parse(Data(sleep.utf8)) == "Sleep" && FocusMonitor.parse(Data(dndLegacy.utf8)) == localized("Do Not Disturb")
              && FocusMonitor.parse(Data(skipsEmpty.utf8)) == "Work", "\(String(describing: FocusMonitor.parse(Data(skipsEmpty.utf8))))")

        // Notifications: parse a real binary plist and read a real SQLite file
        let plist: [String: Any] = ["app": "com.apple.mail", "req": ["titl": "Alice", "subt": "Re: lunch", "body": "See you at 12"]]
        let blob = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
        let p = NotificationReader.parse(blob)
        check("notifications: parse title, subtitle, body and app", p?.title == "Alice · Re: lunch" && p?.body == "See you at 12" && p?.app == "com.apple.mail", "\(String(describing: p))")
        let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-notif-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_exec(db, "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT); CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB, delivered_date REAL); INSERT INTO app VALUES (1, 'com.apple.mail');", nil, nil, nil)
        var ins: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO record VALUES (7, 1, ?, 1000.0)", -1, &ins, nil)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(ins, 1, $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        sqlite3_step(ins); sqlite3_finalize(ins); sqlite3_close(db)
        let read = NotificationReader.read(path: dbPath)
        check("notifications: read rows from the database", read?.count == 1 && read?.first?.title == "Alice · Re: lunch" && read?.first?.app == "com.apple.mail" && read?.first?.id == 7, "\(String(describing: read))")
        check("notifications: unreadable database gives nil", NotificationReader.read(path: "/nonexistent/db") == nil)

        // Calls
        check("calls: needs a live microphone and a call app", CallMonitor.detect(micLive: true, running: ["com.apple.finder", "us.zoom.xos"]) == "Zoom"
              && CallMonitor.detect(micLive: false, running: ["us.zoom.xos"]) == nil && CallMonitor.detect(micLive: true, running: ["com.apple.finder"]) == nil)
    }

    static func screenAskAndKeychain() {
        // Screen
        let r = ScreenGrab.sourceRect(for: CGRect(x: 120, y: 700, width: 300, height: 100), on: CGRect(x: 100, y: 0, width: 1000, height: 900))
        check("screen: AppKit rect to display rect", r == CGRect(x: 20, y: 100, width: 300, height: 100), "\(r)")
        check("window watch: whitespace changes are not changes", !WindowWatch.changed("Build  42%\n", "Build 42%") && WindowWatch.changed("Build 42%", "Build 43%"))
        check("ask: finds links", AskModel.links(in: "docs at https://example.com/x and www.apple.com").count == 2, "\(AskModel.links(in: "docs at https://example.com/x and www.apple.com"))")
        let body = (try? JSONSerialization.jsonObject(with: AskModel.requestBody(text: "hello", question: "what?"))) as? [String: Any]
        let content = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        check("ask: request carries only text, a model and a limit", body?["model"] as? String == "claude-sonnet-5-5" && body?["max_tokens"] as? Int == 1024 && content.contains("hello") && content.contains("what?"))
        check("ask: parses an answer", AskModel.parseAnswer(Data(#"{"content":[{"type":"text","text":"42"},{"type":"text","text":"yes"}]}"#.utf8)) == "42\nyes" && AskModel.parseAnswer(Data("{}".utf8)) == nil)
        let svc = "dev.labs.pillbox.selftest.\(UUID().uuidString)"
        check("keychain: set, get, replace, delete", Keychain.set("k1", svc) && Keychain.get(svc) == "k1" && Keychain.set("k2", svc) && Keychain.get(svc) == "k2" && { Keychain.delete(svc); return Keychain.get(svc) == nil }())
    }

    static func videoSpeedAndWindowDrag() {
        let safari = VideoSpeed.script(rate: 1.5, bundleID: "com.apple.Safari") ?? ""
        let chrome = VideoSpeed.script(rate: 2, bundleID: "com.google.Chrome") ?? ""
        check("video speed: Safari and Chromium scripts set the rate, other apps get none",
              safari.contains("front document") && safari.contains("playbackRate = 1.5") && chrome.contains("active tab") && chrome.contains("playbackRate = 2.0")
              && VideoSpeed.script(rate: 1, bundleID: "com.apple.finder") == nil, "\(safari)")
        check("video speed: AppleScript error numbers map to their own messages",
              VideoSpeed.Failure.classify(number: -1743, message: nil) == .automationDenied && VideoSpeed.Failure.classify(number: -600, message: nil) == .notRunning
              && VideoSpeed.Failure.classify(number: nil, message: "Executing JavaScript through AppleScript is turned off.") == .javaScriptOff
              && VideoSpeed.Failure.classify(number: -1, message: "something else") == .other)
        // Other browsers: each listed browser gets a script that names it and reads its active tab; Safari keeps its own form.
        let listed = VideoSpeed.browsers.map { (id: $0.key, name: $0.value, js: VideoSpeed.script(rate: 1.25, bundleID: $0.key) ?? "") }
        let namedRight = listed.allSatisfy { $0.js.contains("tell application \"\($0.name)\"") && $0.js.contains("playbackRate = 1.25") }
        let chromiumForm = listed.filter { $0.id != "com.apple.Safari" }.allSatisfy { $0.js.contains("active tab") && !$0.js.contains("front document") }
        check("video speed: every listed browser gets a script that names it", listed.count == 6 && namedRight && chromiumForm && VideoSpeed.script(rate: 1, bundleID: nil) == nil,
              "\(listed.map { ($0.id, $0.js) })")
        check("video speed: Edge, Brave, Arc and Chromium use the active tab of the front window",
              ["com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "org.chromium.Chromium"].allSatisfy { (VideoSpeed.script(rate: 1, bundleID: $0) ?? "").contains("tell active tab of front window") })
        // Each failure has its own message, and the Automation and JavaScript cases are not confused.
        let texts = [VideoSpeed.Failure.automationDenied.text, VideoSpeed.Failure.notRunning.text, VideoSpeed.Failure.javaScriptOff.text, VideoSpeed.Failure.other.text]
        check("video speed: each failure has its own localized message",
              texts == [localized("Allow Pillbox to control the browser in Privacy & Security > Automation"), localized("The browser is not running"),
                        localized("Allow JavaScript from Apple Events in the browser"), localized("Could not change the video speed")], "\(texts)")
        check("video speed: a refused automation wins over a JavaScript message, and no number with no message is other",
              VideoSpeed.Failure.classify(number: -1743, message: "JavaScript is off") == .automationDenied && VideoSpeed.Failure.classify(number: nil, message: nil) == .other
              && VideoSpeed.Failure.classify(number: nil, message: "run javascript please") == .javaScriptOff)
        let movedTo = WindowDrag.moved(CGPoint(x: 100, y: 100), by: 10, 20), resizedTo = WindowDrag.resized(CGSize(width: 300, height: 200), by: -500, 10)
        check("window drag: moving up on screen lowers the top-left origin, sizes keep a minimum",
              movedTo == CGPoint(x: 110, y: 80) && resizedTo == CGSize(width: 200, height: 210), "\(movedTo) \(resizedTo)")
    }

    /// The pure geometry behind window dragging and the Accessibility coordinate flip. No window is touched.
    static func windowGeometry() {
        let down = WindowDrag.moved(CGPoint(x: 100, y: 100), by: 0, -30)
        check("window drag: moving down on screen raises the top-left origin", down == CGPoint(x: 100, y: 130), "\(down)")
        let grown = WindowDrag.resized(CGSize(width: 300, height: 200), by: 50, 30)
        let clampedH = WindowDrag.resized(CGSize(width: 500, height: 300), by: 0, -500)
        check("window drag: resizing grows with the pointer and clamps the height to the minimum",
              grown == CGSize(width: 350, height: 230) && clampedH == CGSize(width: 500, height: WindowDrag.minSize.height) && WindowDrag.minSize == CGSize(width: 200, height: 120), "\(grown) \(clampedH)")

        // AX and AppKit differ only by the primary screen's height, so the flip is its own inverse whatever that height is.
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
        let p = CGPoint(x: 37, y: 91)
        check("ax: flipping a point twice gives the same point", near(AXWindow.flipped(AXWindow.flipped(p)), p))
        let rect = CGRect(x: 5, y: 10, width: 20, height: 30)
        let flippedRect = AXWindow.flipped(rect)
        let topEdge = AXWindow.flipped(CGPoint(x: 5, y: 40))   // the AppKit top edge of the rect (maxY), in AX terms
        check("ax: a rect keeps its size, and its AX top is the flipped AppKit top edge",
              abs(flippedRect.minY - topEdge.y) < 1e-9 && flippedRect.minX == 5 && flippedRect.width == 20 && flippedRect.height == 30, "\(flippedRect)")
        check("ax: flipping a rect twice gives the same rect", AXWindow.flipped(AXWindow.flipped(rect)) == rect)
    }
}
