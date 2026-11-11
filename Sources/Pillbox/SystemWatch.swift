import AppKit
import SQLite3
import SwiftUI

// MARK: Brightness HUD

/// Built-in display brightness through the private DisplayServices framework (absent or failing on other setups: no HUD, no crash).
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func current() -> Float? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var v: Float = 0
        return unsafeBitCast(sym, to: GetFn.self)(CGMainDisplayID(), &v) == 0 ? v : nil
    }
}

@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()
    private var timer: Timer?
    private var last: Float?

    func start() {
        last = DisplayBrightness.current()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        guard UserDefaults.standard.object(forKey: "brightnessHUD") as? Bool ?? true, let v = DisplayBrightness.current() else { return }
        defer { last = v }
        guard let l = last, abs(l - v) > 0.01 else { return }
        NotchModel.shared.show(Activity(symbol: v < 0.5 ? "sun.min.fill" : "sun.max.fill", title: "Brightness", tint: .yellow, progress: Double(v), duration: 1.4, priority: .low))
    }
}

// MARK: Focus mode

/// Reads the active Focus from Do Not Disturb's assertions file (needs Full Disk Access).
@MainActor
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()
    @Published private(set) var mode: String?
    private var timer: Timer?
    private var first = true
    static let path = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"

    nonisolated static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = (root["data"] as? [[String: Any]])?.compactMap({ $0["storeAssertionRecords"] as? [[String: Any]] }).flatMap({ $0 }),
              let id = records.compactMap({ ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }).first else { return nil }
        if id.hasSuffix(".default") || id.hasSuffix("donotdisturb") { return L("Do Not Disturb") }
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        poll()
    }

    private func poll() {
        guard UserDefaults.standard.object(forKey: "focusIsland") as? Bool ?? true, let d = FileManager.default.contents(atPath: Self.path) else { return }
        let new = Self.parse(d)
        defer { first = false }
        guard new != mode else { return }
        mode = new
        guard !first else { return }
        NotchModel.shared.show(Activity(symbol: new == nil ? "moon" : "moon.fill", title: new ?? L("Focus off"), tint: new == nil ? .white : .purple, duration: 2.5))
    }
}

// MARK: Notification mirror

struct NotificationItem: Identifiable {
    let id: Int64
    let app: String
    let title: String
    let body: String
    let date: Date
}

/// Reads Notification Center's database (needs Full Disk Access). Read-only; nothing is stored or sent.
enum NotificationReader {
    static let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"

    static func parse(_ blob: Data) -> (app: String, title: String, body: String)? {
        guard let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any], let req = plist["req"] as? [String: Any] else { return nil }
        let title = [req["titl"], req["subt"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
        return (plist["app"] as? String ?? "", title, req["body"] as? String ?? "")
    }

    /// nil when the database cannot be opened (no Full Disk Access).
    static func read(limit: Int = 30, path: String = path) -> [NotificationItem]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        let sql = "SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r LEFT JOIN app a ON r.app_id = a.app_id ORDER BY r.delivered_date DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int(st, 1, Int32(limit))
        var out: [NotificationItem] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(st, 2)))
            guard let p = parse(data) else { continue }
            let ident = sqlite3_column_text(st, 1).map { String(cString: $0) } ?? p.app
            out.append(NotificationItem(id: sqlite3_column_int64(st, 0), app: ident, title: p.title, body: p.body,
                                        date: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(st, 3))))
        }
        return out
    }
}

@MainActor
final class NotificationMirror: ObservableObject {
    static let shared = NotificationMirror()
    @Published private(set) var items: [NotificationItem]?
    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let r = NotificationReader.read()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.items = r } }
        }
    }
}

// MARK: Call in progress

/// Shows a call as an island with its duration while a known call app is running and the microphone is live.
@MainActor
final class CallMonitor: ObservableObject {
    static let shared = CallMonitor()
    static let apps = ["us.zoom.xos": "Zoom", "com.microsoft.teams2": "Teams", "com.microsoft.teams": "Teams", "com.apple.FaceTime": "FaceTime",
                       "net.whatsapp.WhatsApp": "WhatsApp", "com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord", "com.skype.skype": "Skype"]
    @Published private(set) var call: (name: String, since: Date)?
    private var timer: Timer?

    nonisolated static func detect(micLive: Bool, running: [String]) -> String? {
        micLive ? running.compactMap { apps[$0] }.first : nil
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }

    private func poll() {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let name = UserDefaults.standard.object(forKey: "callIsland") as? Bool ?? true ? Self.detect(micLive: PrivacyService.shared.micLive, running: running) : nil
        switch (call, name) {
        case (nil, let n?):
            call = (n, Date())
            NotchModel.shared.show(Activity(symbol: "phone.fill", title: "In a call", subtitle: n, tint: .green, duration: 3, priority: .high))
        case (let c?, nil) where c.name != "": call = nil
        default: break
        }
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
    }
}
