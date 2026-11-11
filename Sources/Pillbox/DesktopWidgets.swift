import Foundation
import AppKit
import Lottie
import SwiftUI

@MainActor
final class DesktopWidgets {
    static let shared = DesktopWidgets()
    private var panel: NSPanel?

    func apply() {
        guard UserDefaults.standard.bool(forKey: "desktopWidgets") else { panel?.orderOut(nil); panel = nil; return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 80, y: 140, width: 330, height: 190), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.isMovableByWindowBackground = true
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: DesktopWidgetView())
            p.setFrameAutosaveName("PillboxDesktopWidgets")
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}

struct DesktopWidgetView: View {
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var music = MusicService.shared
    static let zones = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    /// HH:mm in a given time zone (Text(format:) silently ignores the zone of a Date.FormatStyle).
    nonisolated static func time(_ d: Date, zone id: String) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.timeZone = TimeZone(identifier: id) ?? .current
        return f.string(from: d)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 40, weight: .semibold, design: .rounded))
                    Spacer()
                    if let t = weather.temperature { Label("\(t)°", systemImage: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 16)) }
                }
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(Self.zones, id: \.self) { id in
                        VStack(spacing: 0) {
                            Text(verbatim: id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id).font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(verbatim: Self.time(ctx.date, zone: id)).font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                    }
                }
                if music.hasTrack {
                    Label { Text(verbatim: "\(music.title) · \(music.artist)").lineLimit(1) } icon: { Image(systemName: music.isPlaying ? "play.fill" : "pause.fill") }
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(width: 330, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .environment(\.colorScheme, .dark)
    }
}
