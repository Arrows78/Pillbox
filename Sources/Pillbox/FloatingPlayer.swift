import Foundation
import AppKit
import SwiftUI

enum PlayerSize: Int, CaseIterable, Identifiable {
    case small = 160, medium = 220, large = 300, xlarge = 400
    var id: Int { rawValue }
    var title: String { switch self { case .small: localized("Small"); case .medium: localized("Medium"); case .large: localized("Large"); case .xlarge: localized("Extra large") } }
}

enum SwipeAction { case next, previous }

/// A horizontal swipe on the cover skips tracks; short drags and mostly vertical ones do nothing.
func swipeAction(dx: CGFloat, dy: CGFloat, minimum: CGFloat = 50) -> SwipeAction? {
    guard abs(dx) >= minimum, abs(dx) > abs(dy) * 1.5 else { return nil }
    return dx < 0 ? .next : .previous
}

struct FloatingPlayerView: View {
    @ObservedObject var music = MusicService.shared
    @AppStorage("playerSize") private var size = PlayerSize.medium.rawValue

    var body: some View {
        let side = CGFloat(size)
        VStack(spacing: 8) {
            Group {
                if let a = music.artwork { Image(nsImage: a).resizable().scaledToFill() } else { Rectangle().fill(.white.opacity(0.1)).overlay(Image(systemName: "music.note")) }
            }
            .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 16))
            .gesture(DragGesture(minimumDistance: 20).onEnded { v in
                switch swipeAction(dx: v.translation.width, dy: v.translation.height) { case .next: music.next(); case .previous: music.previous(); case nil: break }
            })
            .accessibilityLabel(Text(verbatim: music.title)).accessibilityHint("Swipe to change track")
            VStack(spacing: 2) {
                Text(verbatim: music.hasTrack ? music.title : localized("Nothing playing")).font(.system(size: side > 250 ? 17 : 13, weight: .semibold)).lineLimit(1)
                Text(verbatim: music.artist).font(.system(size: side > 250 ? 14 : 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }.frame(width: side)
            HStack(spacing: 26) {
                Button { music.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)) }.accessibilityLabel(LocalizedStringKey(music.isPlaying ? "Pause" : "Play"))
                Button { music.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
            }.buttonStyle(.plain)
        }
        .foregroundStyle(.white).padding(16)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 26))
        .contextMenu {
            ForEach(PlayerSize.allCases) { s in Button { size = s.rawValue } label: { Text(verbatim: (s.rawValue == size ? "✓ " : "") + s.title) } }
            Divider()
            Button("Full-screen lyrics") { LyricsScreen.shared.show() }
            Button("Close") { FloatingPlayer.shared.close() }
        }
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class FloatingPlayer {
    static let shared = FloatingPlayer()
    private var panel: NSPanel?
    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : show() }

    func show() {
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.styleAsOverlay(level: .floating); p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: FloatingPlayerView()); host.sizingOptions = [.intrinsicContentSize]
            p.contentView = host; p.setFrameAutosaveName("PillboxFloatingPlayer"); panel = p; return p
        }()
        p.setContentSize(p.contentView?.fittingSize ?? NSSize(width: 260, height: 360))
        if !p.setFrameUsingName("PillboxFloatingPlayer"), let sc = NSScreen.main { p.setFrameOrigin(NSPoint(x: sc.frame.maxX - 300, y: sc.frame.midY)) }
        p.orderFrontRegardless()
        NotchModel.shared.collapse()
    }

    func close() { panel?.orderOut(nil) }
}

// MARK: Full-screen lyrics
