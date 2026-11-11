import AppKit

// MARK: Shake a dragged file to open the shelf

/// Detects a left-right shake: several direction reversals, each after enough travel, within a short window.
struct ShakeDetector {
    var minTravel: CGFloat = 50
    var window: TimeInterval = 0.9
    var reversalsNeeded = 3
    private var lastX: CGFloat?
    private var direction = 0
    private var travel: CGFloat = 0
    private var reversals: [Date] = []

    mutating func reset() { lastX = nil; direction = 0; travel = 0; reversals = [] }

    mutating func add(_ p: CGPoint, at t: Date) -> Bool {
        guard let lx = lastX else { lastX = p.x; return false }
        let dx = p.x - lx
        if abs(dx) < 2 { return false }
        lastX = p.x
        let d = dx > 0 ? 1 : -1
        if d == direction { travel += abs(dx) }
        else {
            if direction != 0, travel >= minTravel { reversals.append(t) }
            direction = d; travel = abs(dx)
        }
        reversals.removeAll { t.timeIntervalSince($0) > window }
        if reversals.count >= reversalsNeeded { reversals = []; return true }
        return false
    }
}

// MARK: Break reminders

/// Suggests a break after a long stretch of activity; one minute without input counts as a break.
struct BreakLogic {
    private var activeSince: Date?
    mutating func tick(idle: TimeInterval, now: Date, every: TimeInterval) -> Bool {
        if idle >= 60 { activeSince = nil; return false }
        guard let s = activeSince else { activeSince = now; return false }
        if now.timeIntervalSince(s) >= every { activeSince = now; return true }
        return false
    }
}

@MainActor
final class BreakReminder {
    static let shared = BreakReminder()
    private var logic = BreakLogic()
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        let minutes = UserDefaults.standard.integer(forKey: "breakReminder")
        guard minutes > 0 else { logic = BreakLogic(); return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if logic.tick(idle: idle, now: Date(), every: Double(minutes) * 60) {
            NotchModel.shared.show(Activity(symbol: "figure.walk", title: L("Time for a break"),subtitle: L("You have been working for %d min", minutes), tint: .green, duration: 8))
        }
    }
}

// MARK: Download progress

struct DownloadItem: Equatable { let name: String; let bytes: Int64 }

enum DownloadScan {
    /// Partial downloads in a folder, with their current size (Safari's .download is a folder, so it is summed).
    static func scan(_ dir: URL) -> [DownloadItem] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && FolderWatcher.temporarySuffixes.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { name in
                let url = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                var total: Int64 = 0
                if isDir.boolValue {
                    let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
                    while let f = en?.nextObject() as? URL { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                } else { total = Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0) }
                return DownloadItem(name: ((name as NSString).deletingPathExtension), bytes: total)
            }.sorted { $0.bytes > $1.bytes }
    }
}

@MainActor
final class DownloadProgress: ObservableObject {
    static let shared = DownloadProgress()
    @Published private(set) var items: [DownloadItem] = []
    private var timer: Timer?

    func start() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard Defaults.bool("downloadAlerts", default: true) else { return }
            DispatchQueue.global(qos: .utility).async {
                let found = DownloadScan.scan(dir)
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.items != found { self?.items = found; NotificationCenter.default.post(name: .notchStateChanged, object: nil) } } }
            }
        }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

// MARK: Build island

/// Shows an island with a stopwatch while `xcodebuild` or `swift build` runs, and its duration when it ends.
@MainActor
final class BuildWatcher: ObservableObject {
    static let shared = BuildWatcher()
    nonisolated static let names: Set<String> = ["xcodebuild", "swift-build"]
    @Published private(set) var since: Date?
    private var timer: Timer?

    nonisolated static func isBuilding(psOutput: String) -> Bool {
        psOutput.split(separator: "\n").contains { names.contains(($0.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent) }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard UserDefaults.standard.object(forKey: "buildIsland") as? Bool ?? true else { return }
            DispatchQueue.global(qos: .utility).async {
                let out = Self.ps()
                let building = Self.isBuilding(psOutput: out)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.update(building) } }
            }
        }
    }

    private nonisolated static func ps() -> String {
        ProcessRunner.run("/bin/ps", ["-axo", "comm="]).output
    }

    func update(_ building: Bool, now: Date = Date()) {
        switch (since, building) {
        case (nil, true): since = now; NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        case (let s?, false):
            since = nil
            NotificationCenter.default.post(name: .notchStateChanged, object: nil)
            let secs = Int(now.timeIntervalSince(s))
            if secs >= 5 { NotchModel.shared.show(Activity(symbol: "hammer.fill", title: L("Build finished"),subtitle: L("%@", TimerService.format(Double(secs))), tint: .green, duration: 4)) }
        default: break
        }
    }
}

// MARK: Bluetooth batteries (AirPods and other accessories)

enum BluetoothBattery {
    /// Connected devices that report a battery, as "Name: L 85% · R 80% · Case 60%".
    static func parse(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = section["device_connected"] as? [[String: Any]] else { return [] }
        let keys: [(String, String)] = [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"), ("device_batteryLevelCase", "Case"), ("device_batteryLevelMain", "")]
        var out: [String] = []
        for entry in connected {
            for (name, info) in entry {
                guard let d = info as? [String: Any] else { continue }
                let parts = keys.compactMap { k, label in (d[k] as? String).map { label.isEmpty ? $0 : "\(label) \($0)" } }
                if !parts.isEmpty { out.append("\(name): " + parts.joined(separator: " · ")) }
            }
        }
        return out.sorted()
    }

    static func read() -> [String] {
        parse(Data(ProcessRunner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]).output.utf8))
    }
}

// MARK: Quick capture from the palette: calendar events and Apple Notes

enum QuickCapture {
    /// "event dinner with Sam tomorrow 8pm" gives the text after the keyword, or nil.
    static func argument(_ query: String, keywords: [String]) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        for k in keywords where q.lowercased().hasPrefix(k + " ") {
            let rest = q.dropFirst(k.count + 1).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// An AppleScript string expression for arbitrary text (quotes, backslashes and line breaks are safe).
    static func appleScriptString(_ s: String) -> String {
        let lines = s.components(separatedBy: .newlines).map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return lines.joined(separator: " & linefeed & ")
    }

    static func addNote(_ text: String) {
        let script = "tell application \"Notes\" to make new note with properties {body:\(appleScriptString(text))}"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = MusicService.run(script) != nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NotchModel.shared.show(Activity(symbol: ok ? "note.text.badge.plus" : "exclamationmark.triangle", title: ok ? L("Saved to Notes") : L("Could not save to Notes"),
                                                    subtitle: ok ? String(text.prefix(60)) : L("Allow Pillbox to control Notes"), tint: ok ? .yellow : .orange))
                }
            }
        }
    }
}
