import Foundation

struct ProviderUsage: Identifiable {
    var id: String { name }
    var name: String
    var symbol = "sparkles"
    var fiveHour = 0, today = 0, week = 0
    var cacheRead = 0
    var days: [(label: String, tokens: Int)] = []
    var lastActivity: Date?
    /// Rate-limit window reported by the CLI itself (Codex), when available.
    var limitPercent: Double?
    var limitWindowMinutes: Int?
    var limitResetsAt: Date?
}

/// Token usage of Claude Code (~/.claude/projects) and Codex (~/.codex/sessions), read from their local logs.
/// Nothing leaves the Mac.
@MainActor
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()
    @Published private(set) var providers: [ProviderUsage] = []
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
            let all = [Self.scanClaude(), Self.scanCodex()].filter { $0.week > 0 || $0.lastActivity != nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.providers = all; self.loading = false } }
        }
    }

    // MARK: Shared helpers

    private nonisolated static func jsonlFiles(in root: URL, since: Date) -> [URL] {
        var out: [URL] = []
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > since { out.append(url) }
        }
        return out
    }

    private nonisolated static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private nonisolated static func finish(_ u: inout ProviderUsage, perDay: [String: Int], now: Date) {
        let f = DateFormatter(); f.dateFormat = "EEE"
        u.days = (0..<7).reversed().map { off in
            let d = Calendar.current.date(byAdding: .day, value: -off, to: now)!
            return (f.string(from: d), perDay[TimerService.dayKey(d)] ?? 0)
        }
    }

    private nonisolated static func add(_ u: inout ProviderUsage, _ perDay: inout [String: Int], tokens: Int, at date: Date, now: Date) {
        u.week += tokens
        perDay[TimerService.dayKey(date), default: 0] += tokens
        if Calendar.current.isDateInToday(date) { u.today += tokens }
        if now.timeIntervalSince(date) < 5 * 3600 { u.fiveHour += tokens }
        if u.lastActivity.map({ date > $0 }) ?? true { u.lastActivity = date }
    }

    // MARK: Claude Code

    nonisolated static func scanClaude(now: Date = Date()) -> ProviderUsage {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "Claude Code")
        var perDay: [String: Int] = [:]
        var seen = Set<String>()
        for url in jsonlFiles(in: root, since: weekAgo) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let msg = obj["message"] as? [String: Any], let usage = msg["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String, let date = parseDate(ts), date > weekAgo else { continue }
                // One API response is logged once per content block: count each id a single time.
                let key = (msg["id"] as? String ?? "") + ((obj["requestId"] as? String) ?? "")
                if !key.isEmpty, !seen.insert(key).inserted { continue }
                let tokens = (usage["input_tokens"] as? Int ?? 0) + (usage["output_tokens"] as? Int ?? 0) + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                u.cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                add(&u, &perDay, tokens: tokens, at: date, now: now)
            }
        }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    // MARK: Codex

    nonisolated static func scanCodex(now: Date = Date()) -> ProviderUsage {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "Codex", symbol: "chevron.left.forwardslash.chevron.right")
        var perDay: [String: Int] = [:]
        var newestLimit: Date?
        for url in jsonlFiles(in: root, since: weekAgo) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var lastTotal = -1
            for line in text.split(separator: "\n") where line.contains("\"token_count\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                      let ts = obj["timestamp"] as? String, let date = parseDate(ts), date > weekAgo else { continue }
                if let info = payload["info"] as? [String: Any],
                   let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int,
                   let last = info["last_token_usage"] as? [String: Any], total != lastTotal {
                    // The same cumulative total repeats when nothing new happened: count it once.
                    lastTotal = total
                    let input = last["input_tokens"] as? Int ?? 0, cached = last["cached_input_tokens"] as? Int ?? 0
                    u.cacheRead += cached
                    add(&u, &perDay, tokens: max(input - cached, 0) + (last["output_tokens"] as? Int ?? 0), at: date, now: now)
                }
                if let p = (payload["rate_limits"] as? [String: Any])?["primary"] as? [String: Any],
                   let pct = p["used_percent"] as? Double, newestLimit.map({ date >= $0 }) ?? true {
                    newestLimit = date
                    u.limitPercent = pct
                    u.limitWindowMinutes = p["window_minutes"] as? Int
                    u.limitResetsAt = (p["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                }
            }
        }
        // A limit window that already reset says nothing about the present.
        if let r = u.limitResetsAt, r < now { u.limitPercent = nil; u.limitResetsAt = nil }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
    }
}
