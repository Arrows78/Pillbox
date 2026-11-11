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

extension NSPanel {
    /// The look the floating panels share: see-through with a shadow, the content draws its own background.
    func styleAsOverlay(level: NSWindow.Level) {
        isOpaque = false; backgroundColor = .clear; hasShadow = true; self.level = level
    }
}

/// A script that scrolls under the webcam. The panel is excluded from screen sharing, so only you see it.
@MainActor
final class Teleprompter: ObservableObject {
    static let shared = Teleprompter()
    /// The text on the panel is the library's current script (see `PrompterStore`), so an edit here is an edit there.
    var script: String {
        get { PrompterStore.shared.current?.text ?? "" }
        set { PrompterStore.shared.setText(newValue) }
    }
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "teleSpeed") } }
    @Published private(set) var offset: CGFloat = 0
    @Published private(set) var running = false
    @Published var editing = false
    @Published var voice: Bool { didSet { UserDefaults.standard.set(voice, forKey: "teleVoice") } }
    private let follower = VoiceFollower()
    /// Measured from the laid-out text; internal so the self-test can give it a height.
    var textHeight: CGFloat = 0
    private var timer: Timer?
    private var panel: NSPanel?
    /// Counts the microphone requests, so only the newest one can start the follower.
    private var accessRequest = 0

    /// The script is laid out 404 points wide: the panel's 460, less 16 on each side and 24 for the text's inset.
    static let textWidth: CGFloat = 404
    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = 230

    init() {
        speed = UserDefaults.standard.double(forKey: "teleSpeed").nonZero ?? 30
        voice = UserDefaults.standard.bool(forKey: "teleVoice")
        editing = script.isEmpty
    }

    /// Starts the library's current script from the top, scrolling by itself or following your voice.
    func begin() {
        if running { toggle() }
        editing = false; restart()
        show()
        toggle()
    }

    /// Moves the text up by `speed` points per second, between the start and the end of the script; stops at the end.
    func tick(_ dt: Double) {
        offset = min(max(0, offset + CGFloat(speed * dt)), textHeight)
        if offset >= textHeight, running { toggle() }
    }

    func toggle() {
        running.toggle()
        timer?.invalidate(); follower.stop()
        guard running else { return }
        textHeight = Self.measure(script, width: Self.textWidth)
        if offset >= textHeight { offset = 0 }   // Play at the end starts again from the top
        if voice {
            accessRequest += 1
            let request = accessRequest   // a pause and a resume while the answer is pending leave only the newest request live
            VoiceFollower.requestAccess { [weak self] ok in
                guard let self, self.running, request == self.accessRequest else { return }
                guard ok else { self.voice = false; self.running = false; self.notice(L("Voice follow needs speech recognition access")); return }
                let started = self.follower.start(script: self.script) { [weak self] fraction in
                    MainActor.assumeIsolated { self?.offset = max(0, CGFloat(fraction) * (self?.textHeight ?? 0)) }
                }
                if !started { self.voice = false; self.running = false; self.notice(L("Voice follow could not start listening")); return }
                self.follower.onEnded = { [weak self] in MainActor.assumeIsolated {
                    guard let self, self.voice else { return }
                    self.voice = false; self.running = false; self.notice(L("Voice follow could not start listening"))
                } }
            }
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick(1.0 / 30) } }
        }
    }

    /// Says in the island why voice following stopped.
    private func notice(_ message: String) {
        NotchModel.shared.show(Activity(symbol: "mic.slash.fill", title: message, tint: .orange))
    }

    func restart() { offset = 0 }

    static func measure(_ text: String, width: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        return ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: [.font: font]).height)
    }

    func show() {
        NotchModel.shared.collapse()
        let size = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let p = panel ?? {
            let p = NotchPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.styleAsOverlay(level: .mainMenu + 2)
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

    func close() { if running { toggle() }; follower.stop(); panel?.orderOut(nil) }
}

struct TeleprompterView: View {
    @ObservedObject var tele = Teleprompter.shared
    @ObservedObject var store = PrompterStore.shared

    var body: some View {
        VStack(spacing: 8) {
            if tele.editing {
                TextEditor(text: Binding(get: { store.current?.text ?? "" }, set: { store.setText($0) })).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .padding(6).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                GeometryReader { g in
                    Text(verbatim: tele.script).font(.system(size: 22, weight: .semibold)).multilineTextAlignment(.center)
                        .frame(width: g.size.width - 24, alignment: .top)
                        .offset(x: 12, y: 40 - tele.offset)
                        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading).clipped()
                        .overlay(alignment: .top) { Rectangle().fill(.orange.opacity(0.7)).frame(height: 2).offset(y: 36) }
                        .overlay {
                            if !tele.running {
                                Label("Click to resume", systemImage: "play.fill").font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.75), in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { tele.toggle() }
                }
                .accessibilityAddTraits(.isButton).accessibilityLabel(LocalizedStringKey(tele.running ? "Pause" : "Play"))
            }
            HStack(spacing: 14) {
                Button { tele.editing.toggle() } label: { Image(systemName: tele.editing ? "checkmark" : "pencil") }.accessibilityLabel(LocalizedStringKey(tele.editing ? "Done editing" : "Edit script"))
                if !tele.editing {
                    Button { tele.restart() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Restart")
                    Button { tele.toggle() } label: { Image(systemName: tele.running ? "pause.fill" : "play.fill") }.accessibilityLabel(LocalizedStringKey(tele.running ? "Pause" : "Play"))
                    Image(systemName: "tortoise.fill").font(.system(size: 10))
                    Slider(value: $tele.speed, in: 10...120).frame(width: 110)
                    Image(systemName: "hare.fill").font(.system(size: 10))
                }
                Spacer()
                Button { tele.close() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
            }.buttonStyle(.plain).font(.system(size: 13))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .frame(width: Teleprompter.panelWidth, height: Teleprompter.panelHeight)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22).fill(.black))
        .environment(\.colorScheme, .dark)
    }
}
