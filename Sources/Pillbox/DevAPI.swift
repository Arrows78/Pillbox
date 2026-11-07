import Foundation
import Network

/// Optional local HTTP endpoint (127.0.0.1) so scripts and CI can show a message in the notch.
/// POST /notify with `Authorization: Bearer <token>` and JSON {"title","message","symbol","duration"}.
@MainActor
final class DevAPI {
    static let shared = DevAPI()
    static let defaultPort: UInt16 = 9998
    private var listener: NWListener?

    static var token: String {
        if let t = UserDefaults.standard.string(forKey: "devAPIToken") { return t }
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(t, forKey: "devAPIToken"); return t
    }

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "devAPIEnabled")
        on ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        let port = NWEndpoint.Port(rawValue: Self.defaultPort)!
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        guard let l = try? NWListener(using: params) else { return }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    private func stop() { listener?.cancel(); listener = nil }

    private nonisolated func handle(_ c: NWConnection) {
        c.start(queue: .global(qos: .utility))
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
            let status = DevAPI.process(data ?? Data())
            let body = status == 200 ? "ok" : "error"
            let resp = "HTTP/1.1 \(status) \(body)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
            c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private nonisolated static func process(_ data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8), let split = text.range(of: "\r\n\r\n") else { return 400 }
        let head = text[..<split.lowerBound], body = text[split.upperBound...]
        guard head.hasPrefix("POST /notify") else { return 404 }
        let token = DispatchQueue.main.sync { MainActor.assumeIsolated { DevAPI.token } }
        guard head.contains("Authorization: Bearer \(token)") else { return 401 }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let title = obj["title"] as? String, title.count <= 120 else { return 400 }
        let message = (obj["message"] as? String).map { String($0.prefix(500)) }
        let symbol = obj["symbol"] as? String ?? "bell.fill"
        let dur = min(max(obj["duration"] as? Double ?? 3, 1), 10)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NotchModel.shared.show(Activity(symbol: symbol, title: title, subtitle: message, duration: dur)) }
        }
        return 200
    }
}
