import Foundation
import Network

/// Optional local HTTP endpoint (127.0.0.1 only), off by default, protected by a per-install bearer token.
///
/// - `POST /notify`  `{"title","message","symbol","duration"}` shows a message in the notch.
/// - `POST /approve` takes a `PreToolUse` hook payload, shows Allow / Deny and answers once the user
///   chooses (or "ask" after two minutes). Without an agent name it is the Claude Code hook and answers with
///   Claude's `hookSpecificOutput`. With `?agent=<name>` (or an `agent` field) any agent can ask: the island
///   names it, and the answer is `{"decision":"allow|deny|ask","reason":...}`. See scripts/agent-approval-hook.sh.
@MainActor
final class DevAPI {
    static let shared = DevAPI()
    nonisolated static let defaultPort: UInt16 = 9998
    private var listener: NWListener?

    /// Keychain item holding the token; the shell hooks read it with `security find-generic-password -s <this> -w`.
    nonisolated static let tokenService = "dev.labs.pillbox.devapi"
    /// The old place of the token, read once and then removed.
    private nonisolated static let legacyKey = "devAPIToken"

    static var token: String { storedToken() }

    /// Replaces the token. Scripts and hooks read it again on their next call; anything holding the old one stops working.
    static func regenerateToken() {
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if !Keychain.set(t, tokenService) { Log.api.error("Could not store the new local API token in the Keychain") }
    }

    /// The token, from the Keychain. A token kept in UserDefaults by an older version moves there on first use.
    /// If the Keychain refuses to store it, the token stays in UserDefaults so the API keeps working.
    nonisolated static func storedToken() -> String {
        if let t = Keychain.get(tokenService), !t.isEmpty { return t }
        let legacy = UserDefaults.standard.string(forKey: legacyKey)
        let t = legacy ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if Keychain.set(t, tokenService) { UserDefaults.standard.removeObject(forKey: legacyKey) }
        else { UserDefaults.standard.set(t, forKey: legacyKey) }
        return t
    }

    func apply() {
        _ = Self.token   // makes sure a token exists before a request can arrive
        Preferences.devAPI.value ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.defaultPort)!)
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { c in DevAPI.handle(c) }
        // A port that is already in use fails the listener after start, so the failure is handled here.
        l.stateUpdateHandler = { state in
            guard case .failed = state else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { DevAPI.shared.listenerFailed(l) } }
        }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    /// Forgets a listener that failed, so that the next `apply()` can start it again.
    private func listenerFailed(_ l: NWListener) {
        guard listener === l else { return }
        Log.api.error("The local API listener failed; the port is probably in use")
        listener = nil; l.cancel()
        NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Local API could not start"), subtitle: localized("Port %d is in use or blocked", Int(Self.defaultPort)), tint: .orange, duration: 6))
    }

    private func stop() { listener?.cancel(); listener = nil }

    // MARK: HTTP

    nonisolated static let maxRequest = 256 * 1024

    /// Whether `buffer` holds a whole request, and where its body starts. Headers and body may arrive in
    /// separate TCP segments, so the caller keeps reading until `Content-Length` bytes of body are there.
    /// Whether the request head carries `Authorization: Bearer <token>`. The header name and the scheme ignore case;
    /// the token must match exactly. An empty token never matches.
    nonisolated static func authorized(_ head: String, token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return head.components(separatedBy: "\r\n").contains { line in
            guard let colon = line.firstIndex(of: ":"),
                  line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "authorization" else { return false }
            let parts = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            return parts.count == 2 && parts[0].lowercased() == "bearer" && parts[1] == token
        }
    }

    nonisolated static func completeness(_ buffer: Data) -> (complete: Bool, bodyStart: Int?) {
        guard let r = buffer.range(of: Data("\r\n\r\n".utf8)) else { return (false, nil) }
        let head = String(decoding: buffer[..<r.lowerBound], as: UTF8.self).lowercased()
        let length = head.components(separatedBy: "\r\n").compactMap { $0.hasPrefix("content-length:") ? Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) : nil }.first ?? 0
        return (buffer.count - r.upperBound >= length, r.upperBound)
    }

    private nonisolated static func handle(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        read(c, Data())
    }

    private nonisolated static func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var buf = buffer; buf.append(data ?? Data())
            if buf.count > maxRequest { return reply(c, 413, "request too large") }
            let state = completeness(buf)
            if !state.complete {
                if error != nil || isComplete { return reply(c, 400, "incomplete request") }
                return read(c, buf)
            }
            route(c, buf, bodyStart: state.bodyStart!)
        }
    }

    private nonisolated static func route(_ c: NWConnection, _ buf: Data, bodyStart: Int) {
        let head = String(decoding: buf[..<(bodyStart - 4)], as: UTF8.self), body = buf[bodyStart...]
        guard authorized(head, token: storedToken()) else { return reply(c, 401, "unauthorized") }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if head.hasPrefix("POST /notify") { notify(c, json) }
        else if head.hasPrefix("POST /approve") { approve(c, json, head: head) }
        else if head.hasPrefix("POST /action") { action(c, json) }
        else if head.hasPrefix("POST /turn") { turn(c, json) }
        else { reply(c, 404, "not found") }
    }

    private nonisolated static func reply(_ c: NWConnection, _ status: Int, _ body: String, json: Bool = false) {
        let resp = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(json ? "application/json" : "text/plain")\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
    }

    private nonisolated static func notify(_ c: NWConnection, _ obj: [String: Any]) {
        guard let title = obj["title"] as? String, title.count <= 120 else { return reply(c, 400, "title required, max 120 characters") }
        let message = (obj["message"] as? String).map { String($0.prefix(500)) }
        let symbol = obj["symbol"] as? String ?? "bell.fill"
        let dur = min(max(obj["duration"] as? Double ?? 3, 1), 10)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NotchModel.shared.show(Activity(symbol: symbol, title: title, subtitle: message, duration: dur)) }
        }
        reply(c, 200, "ok")
    }

    private nonisolated static func action(_ c: NWConnection, _ obj: [String: Any]) {
        let name = obj["tool"] as? String ?? "", args = obj["arguments"] as? [String: Any] ?? [:]
        DispatchQueue.main.async { MainActor.assumeIsolated { let r = AgentActions.run(name, args); reply(c, r.ok ? 200 : 400, r.message) } }
    }

    /// Claude Code `Stop` hook: shows how many tokens the turn that just ended used.
    private nonisolated static func turn(_ c: NWConnection, _ obj: [String: Any]) {
        guard let path = obj["transcript_path"] as? String, AgentTurn.isAllowed(path) else { return reply(c, 400, "transcript_path must be a .jsonl under ~/.claude") }
        DispatchQueue.global(qos: .utility).async {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return reply(c, 400, "unreadable") }
            let n = AgentTurn.tokens(in: text)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                NotchModel.shared.show(Activity(symbol: "sparkles", title: localized("Agent turn finished"),subtitle: localized("%@ tokens", AIUsageService.short(n)), tint: .orange, duration: 5))
                reply(c, 200, "\(n)")
            } }
        }
    }

    /// A name an agent can be shown under: 1 to 40 letters, digits, spaces, dots, dashes or underscores.
    nonisolated static func cleanAgent(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        guard (1...40).contains(name.count), name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return name
    }

    /// The agent named by a request, from `?agent=` in the request line or an `agent` field in the body.
    /// `ok` is false when a name is given but is not a valid one; `agent` is nil when no name is given (Claude Code).
    nonisolated static func requestedAgent(head: String, body: [String: Any]) -> (ok: Bool, agent: String?) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let target = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let query = URLComponents(string: target)?.queryItems?.first { $0.name == "agent" }?.value
        guard let raw = query ?? (body["agent"] as? String) else { return (true, nil) }
        guard let name = cleanAgent(raw) else { return (false, nil) }
        return (true, name)
    }

    /// The tool and what it is about to do, from a hook payload. Claude Code sends `tool_name` and `tool_input`;
    /// other agents may send `tool` or `name`, and `input` or `arguments`.
    nonisolated static func approvalRequest(_ obj: [String: Any]) -> (tool: String, detail: String) {
        let tool = (obj["tool_name"] as? String) ?? (obj["tool"] as? String) ?? (obj["name"] as? String) ?? "A tool"
        let input = (obj["tool_input"] as? [String: Any]) ?? (obj["input"] as? [String: Any]) ?? (obj["arguments"] as? [String: Any]) ?? [:]
        let raw = (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["url"] as? String)
            ?? (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return (tool, String(raw.prefix(240)))
    }

    /// The answer to the hook. Claude Code gets its `hookSpecificOutput` (or `{}` for "ask"); a named agent gets
    /// `{"decision","reason"}`, or `{"decision":"ask"}` when the user did not answer.
    nonisolated static func approvalAnswer(_ decision: String, agent: String?) -> [String: Any] {
        let reason = decision == "deny" ? "Denied from Pillbox" : "Approved from Pillbox"
        guard agent != nil else {
            return decision == "ask" ? [:] : ["hookSpecificOutput": [
                "hookEventName": "PreToolUse", "permissionDecision": decision, "permissionDecisionReason": reason]]
        }
        return decision == "ask" ? ["decision": "ask"] : ["decision": decision, "reason": reason]
    }

    private nonisolated static func approve(_ c: NWConnection, _ obj: [String: Any], head: String) {
        let named = requestedAgent(head: head, body: obj)
        guard named.ok else { return reply(c, 400, "agent must be 1 to 40 letters, digits, spaces, dots, dashes or underscores") }
        let request = approvalRequest(obj)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NotchModel.shared.requestApproval(tool: request.tool, detail: request.detail, agent: named.agent) { decision in
                    let data = (try? JSONSerialization.data(withJSONObject: approvalAnswer(decision, agent: named.agent))) ?? Data("{}".utf8)
                    reply(c, 200, String(data: data, encoding: .utf8) ?? "{}", json: true)
                }
            }
        }
    }
}
