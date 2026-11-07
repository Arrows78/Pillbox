import Foundation

struct Quote: Identifiable, Equatable {
    var id: String { symbol }
    var symbol: String
    var price: Double
    var previousClose: Double
    var series: [Double]
    var state: String          // "Pre-market", "Open", "After-hours", "Closed"
    var change: Double { previousClose == 0 ? 0 : (price - previousClose) / previousClose }
}

struct Watch: Codable, Equatable {
    var symbol: String
    var above: Double?
    var below: Double?
}

@MainActor
final class StocksService: ObservableObject {
    static let shared = StocksService()
    @Published var watchlist: [Watch] = Store.load("stocks.json", as: [Watch].self) ?? [Watch(symbol: "AAPL"), Watch(symbol: "MSFT")]
    @Published var quotes: [String: Quote] = [:]
    @Published var pinned: String? = UserDefaults.standard.string(forKey: "pinnedStock") {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinnedStock") }
    }
    private var timer: Timer?
    private var alerted = Set<String>()

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func add(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty, s.count <= 12, !watchlist.contains(where: { $0.symbol == s }) else { return }
        watchlist.append(Watch(symbol: s)); save(); refresh()
    }

    func remove(_ s: String) {
        watchlist.removeAll { $0.symbol == s }; quotes[s] = nil
        if pinned == s { pinned = nil }
        save()
    }

    /// Alert when the price crosses ±`percent` of the current price (`nil` clears both).
    func setAlert(_ s: String, percent: Double?) {
        guard let i = watchlist.firstIndex(where: { $0.symbol == s }) else { return }
        if let p = percent, let q = quotes[s] {
            watchlist[i].above = q.price * (1 + p / 100); watchlist[i].below = q.price * (1 - p / 100)
        } else { watchlist[i].above = nil; watchlist[i].below = nil }
        alerted.remove(s + "↑"); alerted.remove(s + "↓"); save()
    }

    private func save() { Store.save(watchlist, "stocks.json") }

    func refresh() {
        for w in watchlist { fetch(w.symbol) }
    }

    private func fetch(_ symbol: String) {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=1d&interval=5m&includePrePost=true") else { return }
        var req = URLRequest(url: url); req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data, let q = Self.parse(data, symbol: symbol) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.apply(q) } }
        }.resume()
    }

    nonisolated static func parse(_ data: Data, symbol: String) -> Quote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any], let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any], let price = meta["regularMarketPrice"] as? Double else { return nil }
        let prev = meta["chartPreviousClose"] as? Double ?? meta["previousClose"] as? Double ?? price
        let closes = ((((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"]) as? [Any])?
            .compactMap { $0 as? Double } ?? []
        var state = "Closed"
        if let tp = meta["currentTradingPeriod"] as? [String: [String: Any]] {
            let now = Date().timeIntervalSince1970
            func within(_ k: String) -> Bool {
                guard let s = tp[k]?["start"] as? Double, let e = tp[k]?["end"] as? Double else { return false }
                return now >= s && now < e
            }
            state = within("regular") ? "Open" : within("pre") ? "Pre-market" : within("post") ? "After-hours" : "Closed"
        }
        return Quote(symbol: symbol, price: price, previousClose: prev, series: closes, state: state)
    }

    private func apply(_ q: Quote) {
        quotes[q.symbol] = q
        guard let w = watchlist.first(where: { $0.symbol == q.symbol }) else { return }
        if let a = w.above, q.price >= a, alerted.insert(q.symbol + "↑").inserted {
            NotchModel.shared.show(Activity(symbol: "arrow.up.right.circle.fill", title: L("%@ above %@", q.symbol, String(format: "%.2f", a)),
                                            subtitle: String(format: "%.2f", q.price), tint: .green, duration: 6))
        }
        if let b = w.below, q.price <= b, alerted.insert(q.symbol + "↓").inserted {
            NotchModel.shared.show(Activity(symbol: "arrow.down.right.circle.fill", title: L("%@ below %@", q.symbol, String(format: "%.2f", b)),
                                            subtitle: String(format: "%.2f", q.price), tint: .red, duration: 6))
        }
    }
}
