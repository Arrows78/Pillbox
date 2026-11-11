import Foundation
import Network

/// Optional local HTTP endpoint (127.0.0.1 only), off by default, protected by a per-install bearer token.
///
/// - `POST /notify`  `{"title","message","symbol","duration"}` shows a message in the notch.
/// - `POST /approve` takes a Claude Code `PreToolUse` hook payload, shows Allow / Deny and answers
///   with the hook's JSON decision once the user chooses (or "ask" after two minutes).
@MainActor
final class DevAPI {
    static let shared = DevAPI()
    nonisolated static let defaultPort: UInt16 = 9998
    private var listener: NWListener?

    static var token: String {
        if let t = UserDefaults.standard.string(forKey: "devAPIToken") { return t }
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(t, forKey: "devAPIToken"); return t
    }

    func apply() {
        _ = Self.token   // makes sure a token exists before a request can arrive
        UserDefaults.standard.bool(forKey: "devAPIEnabled") ? start() : stop()
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
        listener = nil; l.cancel()
        NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: L("Local API could not start"), subtitle: L("Port %d is in use or blocked", Int(Self.defaultPort)), tint: .orange, duration: 6))
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
        guard authorized(head, token: UserDefaults.standard.string(forKey: "devAPIToken") ?? "") else { return reply(c, 401, "unauthorized") }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if head.hasPrefix("POST /notify") { notify(c, json) }
        else if head.hasPrefix("POST /approve") { approve(c, json) }
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
                NotchModel.shared.show(Activity(symbol: "sparkles", title: L("Agent turn finished"),subtitle: L("%@ tokens", AIUsageService.short(n)), tint: .orange, duration: 5))
                reply(c, 200, "\(n)")
            } }
        }
    }

    private nonisolated static func approve(_ c: NWConnection, _ obj: [String: Any]) {
        let tool = obj["tool_name"] as? String ?? "A tool"
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        let raw = (input["command"] as? String) ?? (input["file_path"] as? String) ?? (input["url"] as? String)
            ?? (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let detail = String(raw.prefix(240))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NotchModel.shared.requestApproval(tool: tool, detail: detail) { decision in
                    let reason = decision == "deny" ? "Denied from Pillbox" : "Approved from Pillbox"
                    let out: [String: Any] = decision == "ask" ? [:] : ["hookSpecificOutput": [
                        "hookEventName": "PreToolUse", "permissionDecision": decision, "permissionDecisionReason": reason]]
                    let data = (try? JSONSerialization.data(withJSONObject: out)) ?? Data("{}".utf8)
                    reply(c, 200, String(data: data, encoding: .utf8) ?? "{}", json: true)
                }
            }
        }
    }
}
