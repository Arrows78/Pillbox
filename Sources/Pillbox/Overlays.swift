import AppKit
import SwiftUI

/// Paints the top strip of the screen black, behind the menu bar items, so the notch disappears into it.
@MainActor
final class NotchHider {
    static let shared = NotchHider()
    private var window: NSWindow?

    func apply(screen: NSScreen?, height: CGFloat) {
        guard UserDefaults.standard.bool(forKey: "hideNotch"), let screen else { window?.orderOut(nil); window = nil; return }
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
        let w = window ?? {
            let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black; w.isOpaque = true; w.hasShadow = false; w.ignoresMouseEvents = true; w.isReleasedWhenClosed = false
            // Above the wallpaper and desktop icons, below every app window and the menu bar itself.
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window = w; return w
        }()
        w.setFrame(frame, display: true)
        w.orderFrontRegardless()
    }
}

/// A script that scrolls under the webcam. The panel is excluded from screen sharing, so only you see it.
@MainActor
final class Teleprompter: ObservableObject {
    static let shared = Teleprompter()
    @Published var script: String { didSet { UserDefaults.standard.set(script, forKey: "teleScript") } }
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "teleSpeed") } }
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var running = false
    @Published var editing = false
    private var timer: Timer?
    private var panel: NSPanel?

    init() {
        script = UserDefaults.standard.string(forKey: "teleScript") ?? ""
        speed = UserDefaults.standard.double(forKey: "teleSpeed").nonZero ?? 30
        editing = script.isEmpty
    }

    /// Moves the text up by `speed` points per second; never below the start.
    func tick(_ dt: Double) { offset = max(0, offset + CGFloat(speed * dt)) }

    func toggle() {
        running.toggle()
        timer?.invalidate()
        if running { timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick(1.0 / 30) } } }
    }

    func restart() { offset = 0 }

    func show() {
        NotchModel.shared.collapse()
        let size = NSSize(width: 460, height: 230)
        let p = panel ?? {
            let p = NotchPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .mainMenu + 2
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.sharingType = .none
            p.contentView = NSHostingView(rootView: TeleprompterView())
            panel = p; return p
        }()
        if let sc = NotchModel.shared.geometry.screen ?? NSScreen.main {
            p.setFrameOrigin(NSPoint(x: sc.frame.midX - size.width / 2, y: sc.frame.maxY - NotchModel.shared.geometry.height - size.height - 6))
        }
        p.orderFrontRegardless()
    }

    func close() { if running { toggle() }; panel?.orderOut(nil) }
}

struct TeleprompterView: View {
    @ObservedObject var t = Teleprompter.shared

    var body: some View {
        VStack(spacing: 8) {
            if t.editing {
                TextEditor(text: $t.script).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .padding(6).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                GeometryReader { g in
                    Text(verbatim: t.script).font(.system(size: 22, weight: .semibold)).multilineTextAlignment(.center)
                        .frame(width: g.size.width - 24, alignment: .top)
                        .offset(x: 12, y: 40 - t.offset)
                        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading).clipped()
                        .overlay(alignment: .top) { Rectangle().fill(.orange.opacity(0.7)).frame(height: 2).offset(y: 36) }
                }
            }
            HStack(spacing: 14) {
                Button { t.editing.toggle() } label: { Image(systemName: t.editing ? "checkmark" : "pencil") }
                if !t.editing {
                    Button { t.restart() } label: { Image(systemName: "backward.end.fill") }
                    Button { t.toggle() } label: { Image(systemName: t.running ? "pause.fill" : "play.fill") }
                    Image(systemName: "tortoise.fill").font(.system(size: 10))
                    Slider(value: $t.speed, in: 10...120).frame(width: 110)
                    Image(systemName: "hare.fill").font(.system(size: 10))
                }
                Spacer()
                Button { t.close() } label: { Image(systemName: "xmark") }
            }.buttonStyle(.plain).font(.system(size: 13))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .frame(width: 460, height: 230)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black))
        .environment(\.colorScheme, .dark)
    }
}
