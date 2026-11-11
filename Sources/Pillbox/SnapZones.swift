import Foundation
import AppKit
import Lottie
import SwiftUI

@MainActor
final class SnapZones: ObservableObject {
    static let shared = SnapZones()
    /// Every zone, so the drag panel offers the same placements the window snapping supports.
    nonisolated static let zones: [SnapZone] = SnapZone.allCases
    nonisolated static let tile = CGSize(width: 72, height: 56), gap: CGFloat = 8, margin: CGFloat = 12
    static var panelSize: CGSize {
        CGSize(width: CGFloat(zones.count) * tile.width + CGFloat(zones.count - 1) * gap + margin * 2, height: tile.height + margin * 2)
    }

    @Published var hover: SnapZone?
    private var panel: NotchPanel?

    /// Zone under a point, given in the panel's own coordinates (origin bottom-left).
    nonisolated static func zone(at p: CGPoint) -> SnapZone? {
        for (i, z) in zones.enumerated() {
            let r = CGRect(x: margin + CGFloat(i) * (tile.width + gap), y: margin, width: tile.width, height: tile.height)
            if r.contains(p) { return z }
        }
        return nil
    }

    var visible: Bool { panel?.isVisible == true }

    func show() {
        guard !visible, let sc = NotchModel.shared.geometry.screen ?? NSScreen.main else { return }
        let size = Self.panelSize
        let p = panel ?? {
            let p = NotchPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .mainMenu + 4; p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.contentView = NSHostingView(rootView: SnapZonesView())
            panel = p; return p
        }()
        p.setFrameOrigin(NSPoint(x: sc.frame.midX - size.width / 2, y: sc.frame.maxY - NotchModel.shared.geometry.height - size.height - 4))
        p.orderFrontRegardless()
    }

    func update(mouse: NSPoint) {
        guard let p = panel, p.isVisible else { return }
        hover = Self.zone(at: CGPoint(x: mouse.x - p.frame.minX, y: mouse.y - p.frame.minY))
    }

    /// Hides the panel and returns the zone to apply, if the mouse was released over one.
    func finish() -> SnapZone? {
        let z = hover; hover = nil; panel?.orderOut(nil); return z
    }
}

struct SnapZonesView: View {
    @ObservedObject var zones = SnapZones.shared
    var body: some View {
        HStack(spacing: SnapZones.gap) {
            ForEach(SnapZones.zones, id: \.self) { z in
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(zones.hover == z ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12))
                    zoneGlyph(z).padding(10)
                }.frame(width: SnapZones.tile.width, height: SnapZones.tile.height)
            }
        }
        .padding(SnapZones.margin)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black))
    }

    private func zoneGlyph(_ z: SnapZone) -> some View {
        GeometryReader { g in
            let f = z.frame(in: CGRect(origin: .zero, size: g.size))
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
        }
    }
}

// MARK: Lottie idle animation
