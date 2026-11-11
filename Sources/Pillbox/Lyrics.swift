import SwiftUI
import Foundation
import AppKit

/// One sung word and when it starts. Lines from LRCLIB with word stamps (the enhanced LRC format) carry real times;
/// the rest share their line's time evenly between the words.
struct LyricWord: Equatable { let time: Double; let text: String }

struct LyricLine: Identifiable { let id = UUID(); let time: Double; let text: String; var words: [LyricWord] = [] }

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
                Text(verbatim: music.hasTrack ? localized("No synced lyrics for this track") : localized("Nothing playing")).font(.system(size: 28)).foregroundStyle(.secondary)
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
