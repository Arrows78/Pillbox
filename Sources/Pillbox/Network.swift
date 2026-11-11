import Foundation
import AppKit
import Charts
import IOKit
import IOKit.ps
import SwiftUI

struct NetSample: Equatable {
    var t: Date
    var down: Double
    var up: Double
}

extension NetworkRate {
    static let historyWindow: TimeInterval = 600

    static func appending(_ h: [NetSample], _ s: NetSample) -> [NetSample] {
        (h + [s]).filter { s.t.timeIntervalSince($0.t) <= historyWindow }
    }
}

/// Live speeds, then the sparkline in whatever width they leave (up to 54 pt).
struct NetworkLine: View {
    var down: Double
    var up: Double
    var samples: [NetSample]

    var body: some View {
        HStack(spacing: 6) {
            Text("↓ \(NetworkRate.format(down))  ↑ \(NetworkRate.format(up))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            NetSparkline(samples: samples)
        }
    }
}

/// Download (blue) and upload (orange) of the last 10 minutes, each scaled to the busiest moment.
struct NetSparkline: View {
    var samples: [NetSample]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }
            // The window is the last 10 minutes ending now, so a short history sits at the right edge's past, not stretched.
            let windowStart = Date().addingTimeInterval(-NetworkRate.historyWindow)
            let peak = max(samples.map { max($0.down, $0.up) }.max() ?? 0, 1_000)
            for (key, color) in [(\NetSample.down, Color.blue), (\NetSample.up, Color.orange)] {
                var p = Path()
                for (i, s) in samples.enumerated() {
                    let x = CGFloat(s.t.timeIntervalSince(windowStart) / NetworkRate.historyWindow) * size.width
                    let y = size.height - CGFloat(s[keyPath: key] / peak) * (size.height - 1) - 0.5
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(p, with: .color(color.opacity(0.85)), lineWidth: 1)
            }
        }
        .frame(minWidth: 20, maxWidth: 54, minHeight: 12, maxHeight: 12)
        .accessibilityHidden(true)
    }
}

// MARK: Bluetooth audio connect and disconnect islands
