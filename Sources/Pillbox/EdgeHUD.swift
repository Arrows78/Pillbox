import Foundation
import AppKit
import SwiftUI

/// A slim bar on the right edge of the screen instead of an island, for the "Edge bar" style.
@MainActor
final class EdgeHUD {
    static let shared = EdgeHUD()
    private var panel: NSPanel?
    private let model = EdgeModel()
    private var hideTask: Task<Void, Never>?

    nonisolated static let barSize = CGSize(width: 44, height: 200)

    /// Height of the filled part for a level, clamped to the bar.
    nonisolated static func fill(for level: Double, trackHeight: CGFloat) -> CGFloat { trackHeight * CGFloat(min(max(level, 0), 1)) }

    func show(symbol: String, level: Double) {
        guard let sc = NotchModel.shared.geometry.screen ?? NSScreen.main else { return }
        model.symbol = symbol; model.level = level
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.barSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
            p.level = .screenSaver; p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: EdgeBarView(model: model))
            panel = p; return p
        }()
        p.setFrameOrigin(NSPoint(x: sc.frame.maxX - Self.barSize.width - 14, y: sc.frame.midY - Self.barSize.height / 2))
        p.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

@MainActor
final class EdgeModel: ObservableObject {
    @Published var symbol = "speaker.wave.2.fill"
    @Published var level = 0.0
}

struct EdgeBarView: View {
    @ObservedObject var model: EdgeModel
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(height: EdgeHUD.fill(for: model.level, trackHeight: g.size.height))
                }
            }.frame(width: 8)
            Image(systemName: model.symbol).font(.system(size: 14)).foregroundStyle(.white)
        }
        .padding(.vertical, 12).frame(width: EdgeHUD.barSize.width, height: EdgeHUD.barSize.height)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }
}
