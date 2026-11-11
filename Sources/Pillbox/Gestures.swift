import AppKit
import Lottie
import SwiftUI

/// Two quick presses of the Control key open the notch (works on any Mac, needs Input Monitoring).
struct DoubleTapDetector {
    var window: TimeInterval = 0.35
    private var last: Date?
    mutating func press(at t: Date) -> Bool {
        if let l = last, t.timeIntervalSince(l) < window { last = nil; return true }
        last = t; return false
    }
}

@MainActor
final class DoubleTapKey {
    static let shared = DoubleTapKey()
    private var detector = DoubleTapDetector()
    private var monitor: Any?

    func apply() {
        let on = UserDefaults.standard.bool(forKey: "doubleTapOpen")
        if on, monitor == nil {
            PermissionsCenter.shared.checkInputMonitoring(for: "Double-press Control")
            monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
                guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { if DoubleTapKey.shared.detector.press(at: Date()) { NotchModel.shared.toggle() } } }
            }
        } else if !on, let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: Snap zones while dragging a window to the notch

@MainActor
final class SnapZones: ObservableObject {
    static let shared = SnapZones()
    nonisolated static let zones: [SnapZone] = [.left, .right, .full, .center]
    nonisolated static let tile = CGSize(width: 96, height: 56), gap: CGFloat = 10, margin: CGFloat = 12
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

struct LottieIdle: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> NSView {
        let v = LottieAnimationView(filePath: path)
        v.loopMode = .loop; v.contentMode = .scaleAspectFit
        v.animationSpeed = max(UserDefaults.standard.double(forKey: "lottieSpeed"), 0.1)
        v.play()
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: Timer mascots (original emoji, no third-party artwork)

enum Mascot: String, CaseIterable, Identifiable {
    case none, cat, rocket, plant, flame, robot
    var id: String { rawValue }
    var emoji: String? { ["cat": "🐱", "rocket": "🚀", "plant": "🌱", "flame": "🔥", "robot": "🤖"][rawValue] }
    var title: String { rawValue.capitalized }
    static var current: Mascot { Mascot(rawValue: UserDefaults.standard.string(forKey: "mascot") ?? "none") ?? .none }

    /// The mascot grows with the session: seed, sprout, then the full emoji for the plant; others just pulse.
    static func emoji(for mascot: Mascot, progress: Double) -> String? {
        guard let e = mascot.emoji else { return nil }
        guard mascot == .plant else { return e }
        return progress < 0.34 ? "🌱" : progress < 0.67 ? "🌿" : "🌳"
    }
}

// MARK: Desktop widgets

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
