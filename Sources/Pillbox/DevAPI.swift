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
    static let defaultPort: UInt16 = 9998
    private var listener: NWListener?
    private nonisolated(unsafe) static var tokenCache = ""

    static var token: String {
        if let t = UserDefaults.standard.string(forKey: "devAPIToken") { return t }
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(t, forKey: "devAPIToken"); return t
    }

    func apply() {
        Self.tokenCache = Self.token
        UserDefaults.standard.bool(forKey: "devAPIEnabled") ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.defaultPort)!)
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { c in DevAPI.handle(c) }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    private func stop() { listener?.cancel(); listener = nil }

    // MARK: HTTP

    private nonisolated static func handle(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
            guard let text = String(data: data ?? Data(), encoding: .utf8), let split = text.range(of: "\r\n\r\n") else {
                return reply(c, 400, "bad request")
            }
            let head = text[..<split.lowerBound], body = Data(text[split.upperBound...].utf8)
            guard head.contains("Authorization: Bearer \(tokenCache)"), !tokenCache.isEmpty else { return reply(c, 401, "unauthorized") }
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            if head.hasPrefix("POST /notify") { notify(c, json) }
            else if head.hasPrefix("POST /approve") { approve(c, json) }
            else { reply(c, 404, "not found") }
        }
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
