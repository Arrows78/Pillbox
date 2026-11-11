import Foundation

/// What an AI app may ask Pillbox to do. Each call goes through the local API (which needs its token), so the
/// switch in Settings › Developer API stays the only door.
@MainActor
enum AgentActions {
    static func run(_ name: String, _ args: [String: Any]) -> (ok: Bool, message: String) {
        switch name {
        case "start_timer":
            guard let m = args["minutes"] as? Int, (1...180).contains(m) else { return (false, "minutes must be a whole number from 1 to 180") }
            let t = TimerService.shared
            t.reset(); t.mode = .countdown; t.countdownMinutes = m; t.reset(); t.start()
            return (true, "Timer started for \(m) min")
        case "stop_timer":
            TimerService.shared.reset(); return (true, "Timer stopped")
        case "music_control":
            switch args["action"] as? String {
            case "play_pause": MusicService.shared.playPause()
            case "next": MusicService.shared.next()
            case "previous": MusicService.shared.previous()
            default: return (false, "action must be play_pause, next or previous")
            }
            return (true, "Done")
        case "add_to_shelf":
            guard let p = args["path"] as? String else { return (false, "path is required") }
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return (false, "no such file: \(url.path)") }
            ShelfService.shared.add([url]); return (true, "Added \(url.lastPathComponent) to the shelf")
        case "show_notification":
            guard let title = args["title"] as? String, !title.isEmpty, title.count <= 120 else { return (false, "title is required, 120 characters at most") }
            let msg = (args["message"] as? String).map { String($0.prefix(500)) }
            NotchModel.shared.show(Activity(symbol: "bell.fill", title: title, subtitle: msg)); return (true, "Shown")
        case "keep_awake":
            if args["enabled"] as? Bool == false { CaffeineService.shared.stop(); return (true, "Keep awake off") }
            if let m = args["minutes"] as? Int, (1...1440).contains(m) { CaffeineService.shared.start(minutes: m); return (true, "Keep awake for \(m) min") }
            CaffeineService.shared.start(); return (true, "Keep awake on")
        default: return (false, "unknown tool: \(name)")
        }
    }
}

/// A Model Context Protocol server over stdio (`Pillbox --mcp`): newline-delimited JSON-RPC 2.0.
enum MCPServer {
    static func tool(_ name: String, _ desc: String, _ props: [String: Any] = [:], required: [String] = []) -> [String: Any] {
        ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required]]
    }

    static let tools: [[String: Any]] = [
        tool("start_timer", "Start a countdown timer in Pillbox.", ["minutes": ["type": "integer", "minimum": 1, "maximum": 180]], required: ["minutes"]),
        tool("stop_timer", "Stop and reset the timer."),
        tool("music_control", "Control Spotify or Apple Music.", ["action": ["type": "string", "enum": ["play_pause", "next", "previous"]]], required: ["action"]),
        tool("add_to_shelf", "Add a file or folder to Pillbox's shelf.", ["path": ["type": "string"]], required: ["path"]),
        tool("show_notification", "Show a short message in the notch.", ["title": ["type": "string"], "message": ["type": "string"]], required: ["title"]),
        tool("keep_awake", "Keep the Mac awake, or turn it off.", ["minutes": ["type": "integer", "minimum": 1, "maximum": 1440], "enabled": ["type": "boolean"]]),
    ]

    /// The response for one request, or nil for a notification (no `id`). `call` runs a tool.
    static func handle(_ req: [String: Any], call: (String, [String: Any]) -> (ok: Bool, text: String)) -> [String: Any]? {
        guard let method = req["method"] as? String else { return nil }
        guard let id = req["id"] else { return nil }   // notifications get no answer
        func ok(_ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": r] }
        switch method {
        case "initialize":
            let v = (req["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2024-11-05"
            return ok(["protocolVersion": v, "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "pillbox", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"]])
        case "ping": return ok([:])
        case "tools/list": return ok(["tools": tools])
        case "tools/call":
            let p = req["params"] as? [String: Any] ?? [:]
            guard let name = p["name"] as? String, tools.contains(where: { $0["name"] as? String == name }) else {
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool"]]
            }
            let r = call(name, p["arguments"] as? [String: Any] ?? [:])
            return ok(["content": [["type": "text", "text": r.text]], "isError": !r.ok])
        default: return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
    }

    /// Forwards a tool call to the running app's local API.
    static func forward(_ name: String, _ args: [String: Any]) -> (ok: Bool, text: String) {
        // Run from inside the app bundle, the standard domain is Pillbox's own (a suite named like it does not work).
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "devAPIEnabled") else {
            return (false, "Pillbox's local API is off. Turn it on in Pillbox › Settings › Developer API.")
        }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(DevAPI.defaultPort)/action")!)
        req.httpMethod = "POST"; req.timeoutInterval = 10
        req.setValue("Bearer \(DevAPI.storedToken())", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["tool": name, "arguments": args])
        let answer = Answer()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let http = resp as? HTTPURLResponse { answer.set((http.statusCode == 200, String(decoding: data ?? Data(), as: UTF8.self))) }
            else if let err { answer.set((false, "Pillbox is not reachable: \(err.localizedDescription)")) }
            sem.signal()
        }.resume()
        // A late answer lands in `answer` after this returns and is never read.
        if sem.wait(timeout: .now() + 12) == .timedOut { return (false, "Pillbox did not answer within 12 seconds. It may be busy; try again.") }
        return answer.get() ?? (false, "Pillbox is not reachable")
    }

    /// The reply of one forwarded call, written by the URLSession callback and read by the caller.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var result: (ok: Bool, text: String)?
        func set(_ r: (ok: Bool, text: String)) { lock.withLock { if result == nil { result = r } } }
        func get() -> (ok: Bool, text: String)? { lock.withLock { result } }
    }

    /// Reads requests from stdin until it closes. Nothing else may ever be written to stdout.
    static func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if let resp = handle(obj, call: forward), let data = try? JSONSerialization.data(withJSONObject: resp), let s = String(data: data, encoding: .utf8) {
                print(s); fflush(stdout)
            }
        }
    }

    static func configuration(executable: String) -> String {
        let obj: [String: Any] = ["mcpServers": ["pillbox": ["command": executable, "args": ["--mcp"]]]]
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }
}

// MARK: Agent turn tokens (Claude Code Stop hook)

enum AgentTurn {
    /// Tokens used since the last real prompt of the session (tool results are not prompts).
    static func tokens(in transcript: String) -> Int {
        var total = 0
        var seen = Set<String>()
        for line in transcript.split(separator: "\n") {
            guard line.contains("\"type\":\"user\"") || line.contains("\"usage\""),
                  let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let msg = o["message"] as? [String: Any] else { continue }
            if o["type"] as? String == "user" {
                let c = msg["content"]
                let isToolResult = (c as? [[String: Any]])?.contains { $0["type"] as? String == "tool_result" } ?? false
                if !isToolResult { total = 0; seen = [] }   // a new prompt starts a new turn
            } else if let u = msg["usage"] as? [String: Any] {
                let key = (msg["id"] as? String ?? "") + (o["requestId"] as? String ?? "")
                if !key.isEmpty, !seen.insert(key).inserted { continue }
                total += (u["input_tokens"] as? Int ?? 0) + (u["output_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
            }
        }
        return total
    }

    /// Only transcripts under ~/.claude, so the API cannot be used to read arbitrary files.
    static func isAllowed(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.hasPrefix(home + "/.claude/") && p.hasSuffix(".jsonl")
    }
}
