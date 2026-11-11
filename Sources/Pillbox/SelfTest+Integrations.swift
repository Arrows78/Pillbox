import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func stocks() {
        let now = Date().timeIntervalSince1970
        let json = """
        {"chart":{"result":[{"meta":{"regularMarketPrice":110.0,"chartPreviousClose":100.0,
         "currentTradingPeriod":{"pre":{"start":0,"end":1},"regular":{"start":\(now - 100),"end":\(now + 100)},"post":{"start":\(now + 100),"end":\(now + 200)}}},
         "indicators":{"quote":[{"close":[100.0,null,105.0,110.0]}]}}]}}
        """
        let q = StocksService.parse(Data(json.utf8), symbol: "TEST")
        check("quote parses price, change and state", q?.price == 110 && abs((q?.change ?? 0) - 0.10) < 1e-9 && q?.state == "Open", "\(String(describing: q))")
        check("quote skips null closes", q?.series == [100, 105, 110], "\(q?.series ?? [])")
        check("quote rejects garbage", StocksService.parse(Data("{}".utf8), symbol: "X") == nil)
    }

    static func weather() {
        check("weather code mapping", WeatherService.describe(0, day: true).0 == "sun.max.fill" && WeatherService.describe(95, day: true).1 == "Thunderstorm" && WeatherService.describe(61, day: false).1 == "Rain")
        let body = Data(#"{"current":{"temperature_2m":12.6,"weather_code":3,"is_day":1}}"#.utf8)
        check("weather: a 200 body with current conditions parses, rounded to a whole degree", WeatherService.parse(body, status: 200) == WeatherReading(temperature: 13, symbol: "cloud.fill", summary: localized("Overcast")))
        check("weather: any other status is rejected, even with a body", WeatherService.parse(body, status: 500) == nil && WeatherService.parse(body, status: nil) == nil && WeatherService.parse(Data("junk".utf8), status: 200) == nil)
    }

    static func usage() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pillbox-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let claude = root.appendingPathComponent("claude/proj"), codex = root.appendingPathComponent("codex/2026/11/07")
        try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
        try? fm.createDirectory(at: codex, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recent = iso.string(from: now.addingTimeInterval(-600)), old = iso.string(from: now.addingTimeInterval(-3 * 86400))
        // Claude Code logs each content block of one response: the id must be counted once.
        let line = { (id: String, ts: String, i: Int, o: Int) in
            "{\"timestamp\":\"\(ts)\",\"requestId\":\"r\(id)\",\"message\":{\"id\":\"m\(id)\",\"usage\":{\"input_tokens\":\(i),\"output_tokens\":\(o),\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1000}}}"
        }
        let body = [line("1", recent, 100, 50), line("1", recent, 100, 50), line("2", old, 10, 5), "garbage"].joined(separator: "\n")
        try? body.write(to: claude.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let c = AIUsageService.scanClaude(now: now, root: root.appendingPathComponent("claude"))
        check("claude: duplicate message counted once", c.fiveHour == 150, "\(c.fiveHour)")
        // "recent" is ten minutes before now: it counts as today unless that moment falls on yesterday (a run just after midnight).
        let recentIsToday = Calendar.current.isDateInToday(now.addingTimeInterval(-600))
        check("claude: older entries only in the week", c.week == 165 && c.today == (recentIsToday ? 150 : 0), "week \(c.week) today \(c.today)")
        check("claude: cache reads kept apart", c.cacheRead == 2000, "\(c.cacheRead)")
        check("claude: seven day buckets", c.days.count == 7 && c.days.last?.tokens == c.today)

        let reset = now.timeIntervalSince1970 + 3600
        let ev = { (ts: String, total: Int, input: Int, cached: Int, out: Int, resets: Double) in
            "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(out)}},\"rate_limits\":{\"primary\":{\"used_percent\":42.0,\"window_minutes\":300,\"resets_at\":\(resets)}}}}"
        }
        let cbody = [ev(recent, 1000, 1000, 800, 100, reset), ev(recent, 1000, 1000, 800, 100, reset), ev(recent, 2500, 1500, 500, 50, reset)].joined(separator: "\n")
        try? cbody.write(to: codex.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
        let x = AIUsageService.scanCodex(now: now, root: root.appendingPathComponent("codex"))
        check("codex: repeated cumulative total counted once", x.fiveHour == (200 + 100) + (1000 + 50), "\(x.fiveHour)")
        check("codex: reports the limit window", x.limitPercent == 42 && x.limitWindowMinutes == 300, "\(String(describing: x.limitPercent))")
        let past = AIUsageService.scanCodex(now: now.addingTimeInterval(7200), root: root.appendingPathComponent("codex"))
        check("codex: an expired limit window is dropped", past.limitPercent == nil)
    }

    static func reminders() {
        let now = Date()
        let a = RemindersService.parse("call mum tomorrow at 9am", now: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        check("reminder: title without the date words", a.title == "call mum", a.title)
        check("reminder: due tomorrow at 9", a.due.map { Calendar.current.isDate($0, inSameDayAs: tomorrow) && Calendar.current.component(.hour, from: $0) == 9 } == true, "\(String(describing: a.due))")
        let b = RemindersService.parse("buy milk")
        check("reminder: no date keeps the whole text", b.title == "buy milk" && b.due == nil)
        let c = RemindersService.parse("  tomorrow  ")
        check("reminder: only a date keeps the text as title", c.title == "tomorrow" && c.due != nil, c.title)
    }

    static func shortcutsAndSearch() {
        check("shortcuts: list parsing", ShortcutsService.parseList("Morning\n  Send report \n\nWi-Fi off\n") == ["Morning", "Send report", "Wi-Fi off"])
        let g = WebSearch.resolve("swift concurrency", defaultKey: "duckduckgo")
        check("search: default engine", g?.label == "DuckDuckGo" && g?.url.absoluteString == "https://duckduckgo.com/?q=swift%20concurrency", g?.url.absoluteString ?? "nil")
        check("search: bang picks the engine", WebSearch.resolve("yt lofi beats")?.url.absoluteString == "https://www.youtube.com/results?search_query=lofi%20beats")
        check("search: reserved characters are escaped", WebSearch.resolve("a&b=c#d")?.url.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%23d", WebSearch.resolve("a&b=c#d")?.url.absoluteString ?? "nil")
        check("search: translate", WebSearch.resolve("tr good morning", language: "fr")?.url.absoluteString == "https://translate.google.com/?sl=auto&tl=fr&op=translate&text=good%20morning")
        check("search: a lone bang is a normal query", WebSearch.resolve("yt")?.label == "Google" && WebSearch.resolve("   ") == nil)
        check("search: nine engines", WebSearch.engines.count == 9 && Set(WebSearch.engines.map(\.bang)).count == 9)
    }

    /// The teleprompter, its meeting-link finder and the voice that follows the words read aloud.
    static func teleprompterAndPrompterVoice() {
        let t = Teleprompter()
        t.textHeight = 1_000; t.speed = 60; let before = t.offset   // no script written: the library is the user's
        t.tick(0.5)
        check("teleprompter: scrolls at its speed", t.offset - before == 30, "\(t.offset)")
        t.restart()
        check("teleprompter: restart returns to the top", t.offset == 0)
        let pw = PrompterText.words("Good morning, everyone, and thanks for joining.")
        check("prompter: words are normalised with their offsets", pw.map(\.word) == ["good", "morning", "everyone", "and", "thanks", "for", "joining"] && pw[1].start == 5)
        check("calendar: finds a Zoom, Meet or Teams link and ignores others",
              MeetingLink.find(in: [nil, "Room 4", "Join https://us02web.zoom.us/j/123?pwd=x now"])?.host == "us02web.zoom.us"
              && MeetingLink.find(in: ["https://example.com/zoom.us"]) == nil)
        let sw = pw.map(\.word)
        check("prompter: voice advances past the words heard", PrompterText.advance(sw, from: 0, heard: ["Good", "morning"]) == 2)
        check("prompter: voice skips ahead when words are dropped", PrompterText.advance(sw, from: 2, heard: ["thanks", "for"]) == 6)
        check("prompter: unrelated speech does not move it", PrompterText.advance(sw, from: 3, heard: ["banana"]) == 3)
        // A script shorter than the words heard must not crash, and must give an index that makes sense.
        check("prompter: a script shorter than the words heard gives a sensible index",
              PrompterText.advance(["good", "morning"], from: 0, heard: ["Good", "morning"]) == 2
              && PrompterText.advance(["good", "morning"], from: 0, heard: ["x", "good", "morning"]) == 2
              && (0...2).contains(PrompterText.advance(["good", "morning"], from: 1, heard: ["good", "morning", "everyone"])))
    }

    static func tabBar() {
        let bar = NotchModel.expandedSize.width - 44 - 10 - 26 - 10 - 20
        let fits = Tab.allCases.allSatisfy { sel in
            let s = TabBarMetrics.split(Tab.allCases, selected: sel, available: bar)
            let w = s.shown.reduce(-TabBarMetrics.spacing) { $0 + TabBarMetrics.spacing + TabBarMetrics.width($1, selected: $1 == sel) } + (s.more.isEmpty ? 0 : TabBarMetrics.spacing + TabBarMetrics.more)
            return w <= bar && s.shown.contains(sel) && s.shown.count + s.more.count == Tab.allCases.count
        }
        check("tab bar: fits the panel for every selected tab, the rest in the menu", fits)
        let wide = TabBarMetrics.split(Tab.allCases, selected: .calendar, available: 5000)
        check("tab bar: everything shows when there is room", wide.more.isEmpty && wide.shown == Tab.allCases)
    }

    static func prompterSpeeds() {
        check("prompter: speeds map to their nearest preset", PrompterSpeed.nearest(32) == .normal && PrompterSpeed.nearest(100) == .sprint)
        UserDefaults.standard.removeObject(forKey: "teleScript"); UserDefaults.standard.removeObject(forKey: "teleSpeed")
    }

    static func calendarFeeds() {
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:a1\r
        SUMMARY:Team sync\\, weekly\r
        DTSTART;TZID=Europe/Paris:20260211T090000\r
        DTEND;TZID=Europe/Paris:20260211T093000\r
        LOCATION:https://meet.google.com/abc-defg-hij\r
        DESCRIPTION:Long\r
          folded line\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Holiday\r
        DTSTART;VALUE=DATE:20260212\r
        END:VEVENT\r
        END:VCALENDAR
        """
        let ev = ICSParser.parse(ics)
        var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        check("ics: events, time zones, all-day, escaping and folding", ev.count == 2 && ev[0].title == "Team sync, weekly" && paris.component(.hour, from: ev[0].start) == 9
              && ev[0].end.timeIntervalSince(ev[0].start) == 1800 && ev[0].notes == "Long folded line" && ev[1].allDay && ev[1].end.timeIntervalSince(ev[1].start) == 86400
              && MeetingLink.find(in: [ev[0].location]) != nil, "\(ev)")
        check("ics: webcal links become https, others refused", ICSFeeds.url("webcal://example.com/a.ics")?.scheme == "https" && ICSFeeds.url("file:///etc/passwd") == nil && ICSFeeds.url("nonsense") == nil)
    }

    static func githubPRs() {
        let json = #"[{"title":"Fix the thing","url":"https://github.com/o/r/pull/7","number":7,"repository":{"nameWithOwner":"o/r"},"isDraft":true},{"title":"No url","number":1,"repository":{"nameWithOwner":"o/r"}},{"title":"Unsafe","url":"javascript:alert(1)","number":2,"repository":{"nameWithOwner":"o/r"}}]"#
        let prs = GitHubPRs.parse(Data(json.utf8))
        check("github: parses a PR and drops entries without an https link", prs == [PullRequest(title: "Fix the thing", repo: "o/r", number: 7, url: "https://github.com/o/r/pull/7", draft: true)], "\(prs)")
        check("github: garbage gives nothing", GitHubPRs.parse(Data("x".utf8)).isEmpty && GitHubPRs.parse(Data("{}".utf8)).isEmpty)
        // The real gh call: when gh is installed and logged in, both queries must answer with a list (possibly empty), not fail.
        if GitHubPRs.tool != nil, ActionRunner.runShell("\(GitHubPRs.tool!) auth status").status == 0 {
            check("github: the real gh queries answer", GitHubPRs.fetch("--author") != nil && GitHubPRs.fetch("--review-requested") != nil)
        } else {
            print("SKIP  github: the real gh queries answer (gh is not installed or not logged in)")
        }
    }

    static func notificationFeed() {
        // Notification island
        let items = [NotificationItem(id: 5, app: "a", title: "old", body: "", date: Date()), NotificationItem(id: 9, app: "a", title: "new2", body: "", date: Date()), NotificationItem(id: 7, app: "a", title: "new1", body: "", date: Date())]
        check("notifications: only entries newer than the last seen, oldest first", NotificationFeed.fresh(items, after: 5).map(\.title) == ["new1", "new2"] && NotificationFeed.fresh(items, after: 9).isEmpty)
    }

    static func notificationApps() {
        check("notifications: apps listed once, most recent first", NotificationsTab.apps(in: [NotificationItem(id: 3, app: "b", title: "", body: "", date: Date()), NotificationItem(id: 2, app: "a", title: "", body: "", date: Date()), NotificationItem(id: 1, app: "b", title: "", body: "", date: Date())]) == ["b", "a"])
    }

    static func verificationCodes() {
        check("verification codes: found next to a keyword, bare codes, never prices or years",
              NotificationFeed.verificationCode(in: "Your verification code is 482913") == "482913" && NotificationFeed.verificationCode(in: "G-123456 is your Google code") == "123456"
              && NotificationFeed.verificationCode(in: "Code: 123 456") == "123456" && NotificationFeed.verificationCode(in: "2048") == "2048"
              && NotificationFeed.verificationCode(in: "Your order of 12.99 shipped in 2026") == nil && NotificationFeed.verificationCode(in: "See you at 1830") == nil)
        // Keywords match whole words only: "shipping" and "pinned" are not "pin", and a plain code still matches.
        check("verification codes: keywords match whole words, and a code next to 'code' still matches",
              NotificationFeed.verificationCode(in: "Your code is 483920") == "483920" && NotificationFeed.verificationCode(in: "Your order is shipping, 483920") == nil
              && NotificationFeed.verificationCode(in: "Pinned 483920") == nil)
    }

    static func aiUsage() {
        // The chosen order comes first, hidden providers are left out, unknown names keep their place at the end.
        let sample = ["Claude Code", "Codex", "Cursor", "Gemini CLI"].map { ProviderUsage(name: $0) }
        let arranged = AIUsageService.arranged(sample, order: ["Codex", "Claude Code", "Codex"], hidden: ["Cursor"]).map(\.name)
        check("ai usage: chosen order first, hidden providers left out, unknown names keep their place at the end",
              arranged == ["Codex", "Claude Code", "Gemini CLI"], "\(arranged)")
    }

    static func copilotQuota() {
        // Typed as JSON would arrive: the numbers stay Int and Double, not one inferred Double.
        let premium: [String: Any] = ["entitlement": 300, "remaining": 90, "percent_remaining": 30.0]
        let copilot = AIUsageService.copilotUsage(from: ["quota_snapshots": ["premium_interactions": premium] as [String: Any], "quota_reset_date": "2026-12-01"])
        check("copilot: quota becomes a monthly limit", copilot?.limitPercent == 70 && copilot?.today == 210 && copilot?.limitResetsAt != nil && AIUsageService.copilotUsage(from: [:]) == nil,
              "\(String(describing: copilot?.limitPercent)) \(String(describing: copilot?.today)) \(String(describing: copilot?.limitResetsAt))")
    }

    static func mcpProtocol() {
        // MCP protocol
        var calls: [(String, [String: Any])] = []
        let call: (String, [String: Any]) -> (ok: Bool, text: String) = { n, a in calls.append((n, a)); return (n != "stop_timer", "ran \(n)") }
        let `init` = MCPServer.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26"]], call: call)
        check("mcp: initialize echoes the protocol version and announces tools", (`init`?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-03-26" && ((`init`?["result"] as? [String: Any])?["capabilities"] as? [String: Any])?["tools"] != nil)
        check("mcp: a notification gets no answer", MCPServer.handle(["jsonrpc": "2.0", "method": "notifications/initialized"], call: call) == nil)
        let list = MCPServer.handle(["jsonrpc": "2.0", "id": "abc", "method": "tools/list"], call: call)
        let names = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        check("mcp: lists the six tools, and string ids are kept", names.count == 6 && names.contains("start_timer") && list?["id"] as? String == "abc", "\(names)")
        let res = MCPServer.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "start_timer", "arguments": ["minutes": 5]]], call: call)
        check("mcp: a tool call runs the tool and returns its text", calls.last?.0 == "start_timer" && calls.last?.1["minutes"] as? Int == 5 && ((res?["result"] as? [String: Any])?["isError"] as? Bool) == false)
        let bad = MCPServer.handle(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "stop_timer"]], call: call)
        check("mcp: a failing tool is flagged as an error", ((bad?["result"] as? [String: Any])?["isError"] as? Bool) == true)
        let before = calls.count
        let unknown = MCPServer.handle(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "rm_rf"]], call: call)
        check("mcp: an unknown tool is refused and never runs", (unknown?["error"] as? [String: Any])?["code"] as? Int == -32602 && calls.count == before)
        check("mcp: an unknown method is an error", (MCPServer.handle(["jsonrpc": "2.0", "id": 6, "method": "nope"], call: call)?["error"] as? [String: Any])?["code"] as? Int == -32601)
        let cfg = (try? JSONSerialization.jsonObject(with: Data(MCPServer.configuration(executable: "/x/Pillbox").utf8))) as? [String: Any]
        check("mcp: the configuration is valid JSON pointing at --mcp", ((cfg?["mcpServers"] as? [String: Any])?["pillbox"] as? [String: Any])?["args"] as? [String] == ["--mcp"])

        // The API reads until the whole body is there (headers and body can come in separate packets)
        let head = "POST /action HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
        check("api: headers alone are not a request", !DevAPI.completeness(Data(head.utf8)).complete)
        check("api: a partial body is not complete", !DevAPI.completeness(Data((head + "12345").utf8)).complete)
        check("api: the full body completes it, with the right start", DevAPI.completeness(Data((head + "1234567890").utf8)) == (true, head.utf8.count))
        check("api: no Content-Length means no body", DevAPI.completeness(Data("POST /x HTTP/1.1\r\n\r\n".utf8)).complete)
        check("api: no blank line yet is incomplete", !DevAPI.completeness(Data("POST /x HTTP/1.1\r\nContent-Le".utf8)).complete)
    }

    static func agentActions() {
        // Agent actions, validated before anything happens
        check("actions: bad arguments are refused", !AgentActions.run("start_timer", ["minutes": 0]).ok && !AgentActions.run("start_timer", [:]).ok && !AgentActions.run("music_control", ["action": "explode"]).ok
              && !AgentActions.run("add_to_shelf", ["path": "/definitely/not/here"]).ok && !AgentActions.run("show_notification", ["title": ""]).ok && !AgentActions.run("nope", [:]).ok)
        let t = TimerService.shared; let ok = AgentActions.run("start_timer", ["minutes": 7])
        check("actions: start_timer sets a countdown and runs it", ok.ok && t.mode == .countdown && t.countdownMinutes == 7 && t.running); _ = AgentActions.run("stop_timer", [:])
        check("actions: stop_timer stops it", !t.running)
    }

    static func turnTokens() {
        // Turn tokens
        let tr = [#"{"type":"user","message":{"role":"user","content":"first prompt"}}"#,
                  #"{"type":"assistant","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":9999}}}"#,
                  #"{"type":"user","message":{"role":"user","content":"second prompt"}}"#,
                  #"{"type":"assistant","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":0}}}"#,
                  #"{"type":"assistant","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":0}}}"#,
                  #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"#,
                  #"{"type":"assistant","requestId":"r3","message":{"id":"m3","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0}}}"#].joined(separator: "\n")
        check("turn: counts only the last prompt's turn, once per message, without cache reads, across tool results", AgentTurn.tokens(in: tr) == 300 + 15, "\(AgentTurn.tokens(in: tr))")
        check("turn: an empty transcript is zero", AgentTurn.tokens(in: "") == 0)
        let home = NSHomeDirectory()
        check("turn: only .jsonl under ~/.claude are readable", AgentTurn.isAllowed(home + "/.claude/projects/x/s.jsonl") && !AgentTurn.isAllowed("/etc/passwd") && !AgentTurn.isAllowed(home + "/.claude/../.ssh/id_rsa.jsonl") && !AgentTurn.isAllowed(home + "/.claude/settings.json"))
    }
}
