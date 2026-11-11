import AppKit
import Foundation
import SwiftUI

struct StocksTab: View {
    @ObservedObject var stocks = StocksService.shared
    @ObservedObject var model = NotchModel.shared
    @State private var symbol = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: Design.gap) {
                TextField("Add a symbol (AAPL, ^GSPC, BTC-USD…)", text: $symbol).pillField().focused($focused)
                    .onSubmit { stocks.add(symbol); symbol = "" }
                IconButton(symbol: "arrow.clockwise", label: localized("Refresh")) { stocks.refresh() }
            }
            .keepsIslandOpen(while: focused, in: model)
            if stocks.watchlist.isEmpty {
                EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "Your watchlist is empty", message: "Type a symbol above and press Return")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(stocks.watchlist, id: \.symbol) { w in row(w) }
                    }
                }
            }
        }
    }

    private func row(_ watch: Watch) -> some View {
        let quote = stocks.quotes[watch.symbol]
        let up = (quote?.change ?? 0) >= 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(watch.symbol).font(.system(size: 12, weight: .semibold))
                    if stocks.pinned == watch.symbol { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                    if watch.above != nil { Image(systemName: "bell.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                }
                Text(LocalizedStringKey(quote?.state ?? (stocks.failed.contains(watch.symbol) ? "Unavailable" : "…"))).font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 90, alignment: .leading)
            Sparkline(values: quote?.series ?? [], color: up ? .green : .red).frame(height: 22)
            if let quote {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f", quote.price)).font(Design.body.monospaced())
                    Text(String(format: "%@%.2f%%", up ? "+" : "", quote.change * 100)).font(Design.caption.monospaced()).foregroundStyle(up ? .green : .red)
                }.frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .rowCard()
        .onTapGesture {
            // Symbols such as ^GSPC or BTC-USD need escaping to make a valid address.
            if let symbol = watch.symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://finance.yahoo.com/quote/\(symbol)") { NSWorkspace.shared.open(url) }
        }
        .contextMenu {
            Button(LocalizedStringKey(stocks.pinned == watch.symbol ? "Unpin from pill" : "Pin to pill")) { stocks.pinned = stocks.pinned == watch.symbol ? nil : watch.symbol }
            Button("Alert at ±2%") { stocks.setAlert(watch.symbol, percent: 2) }
            Button("Alert at ±5%") { stocks.setAlert(watch.symbol, percent: 5) }
            Button("Clear alert") { stocks.setAlert(watch.symbol, percent: nil) }
            Divider()
            Button("Remove", role: .destructive) { stocks.remove(watch.symbol) }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = g.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = g.size.height * (1 - CGFloat(hi == lo ? 0.5 : (v - lo) / (hi - lo)))
                        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }.stroke(color, lineWidth: 1.5)
            }
        }
    }
}
