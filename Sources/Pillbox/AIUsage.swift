import Foundation
import SQLite3

struct ProviderUsage: Identifiable {
    var id: String { name }
    var name: String
    var symbol = "sparkles"
    /// What the numbers count: "tokens" for most providers, "edits" for Cursor's AI-written code, "requests" for Copilot.
    var unit = "tokens"
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
    var alertState = UsageAlertState()
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
        let copilot = UserDefaults.standard.bool(forKey: Self.copilotKey)
        DispatchQueue.global(qos: .utility).async {
            var all = [Self.scanClaude(), Self.scanCodex(), Self.scanGemini(), Self.scanOpenCode(), Self.scanCursor()].filter { $0.week > 0 || $0.lastActivity != nil }
            if copilot, let c = Self.fetchCopilot() { all.append(c) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.providers = all; self.loading = false; self.checkAlerts(all) } }
        }
    }

    nonisolated static let copilotKey = "copilotUsage"

    // MARK: Shared helpers

    private nonisolated static func jsonlFiles(in root: URL, since: Date) -> [(url: URL, mtime: Date, size: Int)] {
        var out: [(URL, Date, Int)] = []
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "jsonl", let v = try? url.resourceValues(forKeys: keys),
                  let m = v.contentModificationDate, m > since else { continue }
            out.append((url, m, v.fileSize ?? 0))
        }
        return out
    }

    private nonisolated static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Calls `body` with the bytes of every line containing `needle`, without decoding the other lines.
    /// Session logs are hundreds of megabytes: decoding them as strings is far too slow.
    private nonisolated static func forEachLine(of data: Data, containing needle: String, _ body: (UnsafeRawBufferPointer) -> Void) {
        let n = Array(needle.utf8)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var pos = 0
            while pos < raw.count {
                let rest = raw.count - pos
                let nl = memchr(base + pos, 0x0A, rest)
                let len = nl.map { base.distance(to: UnsafeRawPointer($0)) - pos } ?? rest
                if len >= n.count, memmem(base + pos, len, n, n.count) != nil {
                    body(UnsafeRawBufferPointer(start: base + pos, count: len))
                }
                pos += len + 1
            }
        }
    }

    /// Value following `"key":` as a string (quoted) or an integer, scanned straight from the bytes.
    private nonisolated static func field(_ line: UnsafeRawBufferPointer, _ prefix: String) -> Substring? {
        let p = Array(prefix.utf8)
        guard let base = line.baseAddress, let hit = memmem(base, line.count, p, p.count) else { return nil }
        let start = base.distance(to: UnsafeRawPointer(hit)) + p.count
        var end = start
        while end < line.count, line[end] != 0x22, line[end] != 0x2C, line[end] != 0x7D { end += 1 }
        return String(decoding: UnsafeRawBufferPointer(rebasing: line[start..<end]), as: UTF8.self)[...]
    }

    private nonisolated static func int(_ line: UnsafeRawBufferPointer, _ key: String) -> Int {
        field(line, "\"\(key)\":").flatMap { Int($0) } ?? 0
    }

    private final class Cache<Entry>: @unchecked Sendable {
        private var items: [String: (mtime: Date, size: Int, entries: Entry)] = [:]
        private let lock = NSLock()
        func get(_ path: String, _ mtime: Date, _ size: Int) -> Entry? {
            lock.lock(); defer { lock.unlock() }
            guard let i = items[path], i.mtime == mtime, i.size == size else { return nil }
            return i.entries
        }
        func set(_ path: String, _ mtime: Date, _ size: Int, _ e: Entry) {
            lock.lock(); items[path] = (mtime, size, e); lock.unlock()
        }
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

    private struct ClaudeEntry { var key: String; var date: Date; var tokens: Int; var cacheRead: Int }
    private nonisolated static let claudeCache = Cache<[ClaudeEntry]>()

    nonisolated static func scanClaude(now: Date = Date(),
                                       root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")) -> ProviderUsage {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "Claude Code")
        var perDay: [String: Int] = [:]
        var seen = Set<String>()
        for f in jsonlFiles(in: root, since: weekAgo) {
            let entries: [ClaudeEntry]
            if let cached = claudeCache.get(f.url.path, f.mtime, f.size) { entries = cached }
            else {
                var parsed: [ClaudeEntry] = []
                if let data = try? Data(contentsOf: f.url, options: .mappedIfSafe) {
                    forEachLine(of: data, containing: "\"usage\"") { line in
                        guard let ts = field(line, "\"timestamp\":\""), let date = parseDate(String(ts)) else { return }
                        let key = (field(line, "\"message\":{\"id\":\"").map(String.init) ?? "") + (field(line, "\"requestId\":\"").map(String.init) ?? "")
                        // Output of a response is logged once per content block: the id is what makes it unique.
                        parsed.append(ClaudeEntry(key: key, date: date,
                                                  tokens: int(line, "input_tokens") + int(line, "output_tokens") + int(line, "cache_creation_input_tokens"),
                                                  cacheRead: int(line, "cache_read_input_tokens")))
                    }
                }
                claudeCache.set(f.url.path, f.mtime, f.size, parsed)
                entries = parsed
            }
            for e in entries where e.date > weekAgo {
                if !e.key.isEmpty, !seen.insert(e.key).inserted { continue }
                u.cacheRead += e.cacheRead
                add(&u, &perDay, tokens: e.tokens, at: e.date, now: now)
            }
        }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    // MARK: Codex

    private struct CodexFile {
        var entries: [(date: Date, tokens: Int, cached: Int)] = []
        var limit: (date: Date, percent: Double, window: Int?, resets: Date?)?
    }
    private nonisolated static let codexCache = Cache<CodexFile>()

    nonisolated static func scanCodex(now: Date = Date(),
                                      root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) -> ProviderUsage {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "Codex", symbol: "chevron.left.forwardslash.chevron.right")
        var perDay: [String: Int] = [:]
        var newest: (date: Date, percent: Double, window: Int?, resets: Date?)?
        for f in jsonlFiles(in: root, since: weekAgo) {
            let file: CodexFile
            if let cached = codexCache.get(f.url.path, f.mtime, f.size) { file = cached }
            else {
                var parsed = CodexFile()
                var lastTotal = -1
                if let data = try? Data(contentsOf: f.url, options: .mappedIfSafe) {
                    forEachLine(of: data, containing: "\"token_count\"") { line in
                        guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                              let payload = obj["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                              let ts = obj["timestamp"] as? String, let date = parseDate(ts) else { return }
                        if let info = payload["info"] as? [String: Any],
                           let total = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int,
                           let last = info["last_token_usage"] as? [String: Any], total != lastTotal {
                            // The same cumulative total repeats when nothing new happened: count it once.
                            lastTotal = total
                            let input = last["input_tokens"] as? Int ?? 0, cached = last["cached_input_tokens"] as? Int ?? 0
                            parsed.entries.append((date, max(input - cached, 0) + (last["output_tokens"] as? Int ?? 0), cached))
                        }
                        if let p = (payload["rate_limits"] as? [String: Any])?["primary"] as? [String: Any],
                           let pct = p["used_percent"] as? Double, parsed.limit.map({ date >= $0.date }) ?? true {
                            parsed.limit = (date, pct, p["window_minutes"] as? Int, (p["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) })
                        }
                    }
                }
                codexCache.set(f.url.path, f.mtime, f.size, parsed)
                file = parsed
            }
            for e in file.entries where e.date > weekAgo {
                u.cacheRead += e.cached
                add(&u, &perDay, tokens: e.tokens, at: e.date, now: now)
            }
            if let l = file.limit, newest.map({ l.date >= $0.date }) ?? true { newest = l }
        }
        // A limit window that already reset says nothing about the present.
        if let l = newest, let r = l.resets, r > now { u.limitPercent = l.percent; u.limitWindowMinutes = l.window; u.limitResetsAt = r }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
    }
}

// MARK: Gemini CLI, OpenCode, Cursor and GitHub Copilot

extension AIUsageService {
    private nonisolated static func jsonFiles(in root: URL, since: Date) -> [URL] {
        var out: [URL] = []
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "json", let m = try? url.resourceValues(forKeys: keys).contentModificationDate, m > since else { continue }
            out.append(url)
        }
        return out
    }

    /// Gemini CLI keeps each chat in ~/.gemini/tmp/<project>/chats/session-*.json; every model reply carries its token counts.
    nonisolated static func scanGemini(now: Date = Date(), root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp")) -> ProviderUsage {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "Gemini CLI", symbol: "diamond.fill")
        var perDay: [String: Int] = [:]
        for f in jsonFiles(in: root, since: weekAgo) where f.deletingLastPathComponent().lastPathComponent == "chats" {
            guard let data = try? Data(contentsOf: f), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = root["messages"] as? [[String: Any]] else { continue }
            for m in messages where m["type"] as? String == "gemini" {
                guard let ts = m["timestamp"] as? String, let date = parseDate(ts), date > weekAgo, let t = m["tokens"] as? [String: Any] else { continue }
                let cached = t["cached"] as? Int ?? 0
                u.cacheRead += cached
                add(&u, &perDay, tokens: max((t["input"] as? Int ?? 0) - cached, 0) + (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0), at: date, now: now)
            }
        }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    /// OpenCode stores one JSON per message under storage/message/<session>/; assistant messages carry `tokens` and `time.created` (ms).
    nonisolated static func scanOpenCode(now: Date = Date(), root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/storage/message")) -> ProviderUsage {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var u = ProviderUsage(name: "OpenCode", symbol: "terminal")
        var perDay: [String: Int] = [:]
        for f in jsonFiles(in: root, since: weekAgo) {
            guard let data = try? Data(contentsOf: f), let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any], m["role"] as? String == "assistant",
                  let ms = (m["time"] as? [String: Any])?["created"] as? Double, let t = m["tokens"] as? [String: Any] else { continue }
            let date = Date(timeIntervalSince1970: ms / 1000)
            guard date > weekAgo else { continue }
            let cache = t["cache"] as? [String: Any]
            u.cacheRead += cache?["read"] as? Int ?? 0
            add(&u, &perDay, tokens: (t["input"] as? Int ?? 0) + (t["output"] as? Int ?? 0) + (t["reasoning"] as? Int ?? 0) + (cache?["write"] as? Int ?? 0), at: date, now: now)
        }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    /// Cursor logs no tokens, but ~/.cursor/ai-tracking/ai-code-tracking.db records every piece of code its AI wrote: counted as edits.
    nonisolated static func scanCursor(now: Date = Date(), path: String = NSHomeDirectory() + "/.cursor/ai-tracking/ai-code-tracking.db") -> ProviderUsage {
        var u = ProviderUsage(name: "Cursor", symbol: "cursorarrow.rays", unit: "edits")
        var perDay: [String: Int] = [:]
        guard FileManager.default.fileExists(atPath: path) else { return u }
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var db: OpaquePointer?
        guard sqlite3_open_v2("file:\(path)?mode=ro&immutable=1", &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { sqlite3_close(db); return u }
        defer { sqlite3_close(db) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT createdAt FROM ai_code_hashes WHERE createdAt > ?", -1, &st, nil) == SQLITE_OK else { return u }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, Int64(weekAgo.timeIntervalSince1970 * 1000))
        while sqlite3_step(st) == SQLITE_ROW {
            let ms = sqlite3_column_double(st, 0)
            add(&u, &perDay, tokens: 1, at: Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms), now: now)
        }
        finish(&u, perDay: perDay, now: now)
        return u
    }

    /// GitHub Copilot's monthly quota, through the GitHub CLI's own login (opt-in; Pillbox stores no token).
    nonisolated static func fetchCopilot() -> ProviderUsage? {
        guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let r = ActionRunner.runShell("\"\(gh)\" api /copilot_internal/user", timeout: 15)
        guard r.status == 0, let data = r.output.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return copilotUsage(from: json)
    }

    /// `quota_snapshots.premium_interactions` is the monthly budget of premium requests; `quota_reset_date` when it refills.
    nonisolated static func copilotUsage(from json: [String: Any], now: Date = Date()) -> ProviderUsage? {
        guard let snapshots = json["quota_snapshots"] as? [String: Any],
              let premium = (snapshots["premium_interactions"] ?? snapshots["chat"]) as? [String: Any] else { return nil }
        var u = ProviderUsage(name: "Copilot", symbol: "circle.hexagongrid.fill", unit: "requests")
        let entitlement = premium["entitlement"] as? Int ?? 0, remaining = premium["remaining"] as? Int ?? 0
        if premium["unlimited"] as? Bool != true, entitlement > 0 {
            u.limitPercent = 100 - (premium["percent_remaining"] as? Double ?? Double(remaining) * 100 / Double(entitlement))
            u.today = entitlement - remaining; u.week = u.today
            u.limitWindowMinutes = 30 * 24 * 60
            if let s = json["quota_reset_date"] as? String {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "UTC")
                u.limitResetsAt = f.date(from: s)
            }
        }
        u.lastActivity = now
        finish(&u, perDay: [:], now: now)
        return u
    }
}
