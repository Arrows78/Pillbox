import Foundation

/// Token usage of Claude Code, read from its local session logs (~/.claude/projects). Nothing leaves the Mac.
@MainActor
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()

    struct Snapshot {
        var fiveHour = 0, today = 0, week = 0
        var cacheRead = 0
        var days: [(label: String, tokens: Int)] = []
        var lastActivity: Date?
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var loading = false
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let snap = Self.scan()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.snapshot = snap; self.loading = false } }
        }
    }

    nonisolated static func scan(now: Date = Date()) -> Snapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var snap = Snapshot()
        var perDay: [String: Int] = [:]
        var seen = Set<String>()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        let cal = Calendar.current
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > weekAgo,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let msg = obj["message"] as? [String: Any], let u = msg["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String, let date = iso.date(from: ts) ?? isoPlain.date(from: ts), date > weekAgo else { continue }
                // One API response is logged once per content block: count each id a single time.
                let key = (msg["id"] as? String ?? "") + ((obj["requestId"] as? String) ?? "")
                if !key.isEmpty, !seen.insert(key).inserted { continue }
                let tokens = (u["input_tokens"] as? Int ?? 0) + (u["output_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
                snap.cacheRead += u["cache_read_input_tokens"] as? Int ?? 0
                snap.week += tokens
                perDay[TimerService.dayKey(date), default: 0] += tokens
                if cal.isDateInToday(date) { snap.today += tokens }
                if now.timeIntervalSince(date) < 5 * 3600 { snap.fiveHour += tokens }
                if snap.lastActivity.map({ date > $0 }) ?? true { snap.lastActivity = date }
            }
        }
        let f = DateFormatter(); f.dateFormat = "EEE"
        snap.days = (0..<7).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: now)!
            return (f.string(from: d), perDay[TimerService.dayKey(d)] ?? 0)
        }
        return snap
    }

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
    }
}
