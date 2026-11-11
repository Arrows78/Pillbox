import AppKit
import SwiftUI

enum PlayerSize: Int, CaseIterable, Identifiable {
    case small = 160, medium = 220, large = 300, xlarge = 400
    var id: Int { rawValue }
    var title: String { switch self { case .small: L("Small"); case .medium: L("Medium"); case .large: L("Large"); case .xlarge: L("Extra large") } }
    static var current: PlayerSize { PlayerSize(rawValue: UserDefaults.standard.integer(forKey: "playerSize")) ?? .medium }
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
                Text(verbatim: music.hasTrack ? music.title : L("Nothing playing")).font(.system(size: side > 250 ? 17 : 13, weight: .semibold)).lineLimit(1)
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
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating; p.isMovableByWindowBackground = true
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

/// A lyric line that fills word by word: sung words in full white, the rest dimmed. Moves with the playhead.
struct LyricWordsText: View {
    let line: LyricLine
    let position: Double

    var body: some View {
        let current = line.words.lastIndex { $0.time <= position + 0.2 } ?? -1
        line.words.enumerated().reduce(Text("")) { text, word in
            text + Text(verbatim: (word.offset == 0 ? "" : " ") + word.element.text)
                .foregroundColor(word.offset <= current ? .white : .white.opacity(0.4))
        }
    }
}

/// `LyricWordsText` redrawn ten times a second, so the highlight follows the music between polls.
struct LiveLyricLine: View {
    let line: LyricLine
    @ObservedObject var music = MusicService.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            LyricWordsText(line: line, position: music.playhead(at: context.date))
        }
    }
}

struct LyricsScreenView: View {
    @ObservedObject var music = MusicService.shared

    /// Index of the line being sung, or nil before the first one.
    nonisolated static func currentIndex(_ lines: [LyricLine], at t: Double) -> Int? { lines.lastIndex { $0.time <= t + 0.2 } }

    var body: some View {
        let idx = Self.currentIndex(music.lyrics, at: music.position)
        VStack(spacing: 22) {
            Spacer()
            if music.lyrics.isEmpty {
                Text(verbatim: music.hasTrack ? L("No synced lyrics for this track") : L("Nothing playing")).font(.system(size: 28)).foregroundStyle(.secondary)
            } else {
                ForEach(((idx ?? -1) - 1)...((idx ?? -1) + 2), id: \.self) { i in
                    if music.lyrics.indices.contains(i) {
                        Group {
                            if i == idx { LiveLyricLine(line: music.lyrics[i]) } else { Text(verbatim: music.lyrics[i].text) }
                        }.multilineTextAlignment(.center)
                            .font(.system(size: i == idx ? 56 : 32, weight: .bold)).opacity(i == idx ? 1 : 0.35)
                            .animation(.easeInOut(duration: 0.3), value: idx)
                    }
                }
            }
            Spacer()
            Text(verbatim: music.hasTrack ? "\(music.title) · \(music.artist)" : "").font(.system(size: 16)).foregroundStyle(.secondary)
            Text("Press Esc or click to close").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.white).padding(60).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.94))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
final class LyricsScreen {
    static let shared = LyricsScreen()
    private var window: NSWindow?
    private var monitor: Any?

    func show() {
        guard let sc = NSScreen.main, window == nil else { return }
        let w = NotchPanel(contentRect: sc.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .screenSaver; w.hasShadow = false
        w.contentView = NSHostingView(rootView: LyricsScreenView().onTapGesture { LyricsScreen.shared.close() })
        w.hidesOnDeactivate = false   // Pillbox is never the active app: a panel would hide itself at once
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil); window = w
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { DispatchQueue.main.async { MainActor.assumeIsolated { LyricsScreen.shared.close() } }; return nil }
            return e
        }
        NotchModel.shared.collapse()
    }

    func close() {
        window?.orderOut(nil); window = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: Copy stack: copy several things, paste them back in order

struct CopyStack {
    private(set) var items: [String] = []
    static let cap = 20
    mutating func push(_ s: String) { items.append(s); if items.count > Self.cap { items.removeFirst() } }
    mutating func pop() -> String? { items.isEmpty ? nil : items.removeFirst() }
    mutating func clear() { items = [] }
}

@MainActor
final class CopyStackStore: ObservableObject {
    static let shared = CopyStackStore()
    @Published private(set) var stack = CopyStack()
    var enabled: Bool { UserDefaults.standard.bool(forKey: "copyStack") }

    func noteCopy(_ text: String) {
        guard enabled else { return }
        stack.push(text)
        NotchModel.shared.show(Activity(symbol: "square.stack.fill", title: L("Stack: %d", stack.items.count), subtitle: String(text.prefix(40)), tint: .blue, duration: 1.2))
    }

    /// Pastes the oldest copy and removes it from the stack.
    func pasteNext() {
        guard let s = stack.pop() else { NotchModel.shared.show(Activity(symbol: "square.stack", title: "The copy stack is empty", duration: 1.5)); return }
        ClipboardService.shared.paste(ClipItem(text: s))
    }

    func clear() { stack.clear() }
}

// MARK: Calculation history

struct CalcHistory {
    private(set) var entries: [String]
    static let cap = 10
    init(_ e: [String] = []) { entries = e }
    mutating func add(expression: String, result: String) {
        let line = "\(expression) = \(result)"
        entries.removeAll { $0 == line }
        entries.insert(line, at: 0)
        if entries.count > Self.cap { entries.removeLast() }
    }
    /// The result part of an entry, for copying it again.
    static func result(of entry: String) -> String { entry.components(separatedBy: " = ").last ?? entry }
}

@MainActor
enum CalcStore {
    static var history = CalcHistory(Store.load("calc.json", as: [String].self) ?? [])
    static func record(_ expr: String, _ result: String) { history.add(expression: expr, result: result); Store.save(history.entries, "calc.json") }
}
