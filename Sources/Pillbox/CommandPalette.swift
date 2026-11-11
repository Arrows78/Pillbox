import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let run: @MainActor () -> Void

    /// `title` is an English key, localised here so filtering matches what the user reads.
    init(title: String, symbol: String, run: @escaping @MainActor () -> Void) {
        self.title = localized(title); self.symbol = symbol; self.run = run
    }
    init(localized title: String, symbol: String, run: @escaping @MainActor () -> Void) {
        self.title = title; self.symbol = symbol; self.run = run
    }
}

@MainActor
final class PaletteModel: ObservableObject {
    /// Changing the query rebuilds the rows; so does opening the palette, so live labels (keep awake, microphone) are current.
    @Published var query = "" { didSet { refresh() } }
    @Published var selection = 0
    /// The rows for the current query. Built when the query changes or the palette opens, not on every redraw.
    private(set) var commands: [PaletteCommand] = []

    init() { refresh() }

    func refresh() { commands = buildCommands() }

    private func buildCommands() -> [PaletteCommand] {
        let notch = NotchModel.shared, timers = TimerService.shared
        var list = Tab.visible.enumerated().map { i, tab in
            PaletteCommand(localized: localized("Go to %@", tab.title) + (i < 9 ? "  ⌘\(i + 1)" : ""), symbol: tab.symbol) { notch.expand(tab) }
        }
        list += [
            PaletteCommand(title: CaffeineService.shared.active ? "Turn keep awake off" : "Turn keep awake on", symbol: "cup.and.saucer.fill") { CaffeineService.shared.toggle() },
            PaletteCommand(title: "Start focus session", symbol: "timer") { timers.mode = .focus; timers.start() },
            PaletteCommand(title: "Start stopwatch", symbol: "stopwatch") { timers.mode = .stopwatch; timers.start() },
            PaletteCommand(title: AudioControl.shared.micMuted ? "Unmute microphone" : "Mute microphone", symbol: "mic.slash.fill") { AudioControl.shared.toggleMic() },
            PaletteCommand(title: "Video speed 1×", symbol: "speedometer") { VideoSpeed.set(1) },
            PaletteCommand(title: "Video speed 1.5×", symbol: "speedometer") { VideoSpeed.set(1.5) },
            PaletteCommand(title: "Video speed 2×", symbol: "speedometer") { VideoSpeed.set(2) },
            PaletteCommand(title: "External display brightness up", symbol: "sun.max.fill") { ExternalBrightness.step(10) },
            PaletteCommand(title: "External display brightness down", symbol: "sun.min.fill") { ExternalBrightness.step(-10) },
            PaletteCommand(title: "Keyboard backlight up", symbol: "light.max") { KeyboardBacklight.step(0.25) },
            PaletteCommand(title: "Keyboard backlight down", symbol: "light.min") { KeyboardBacklight.step(-0.25) },
            PaletteCommand(title: "Turn keyboard backlight off", symbol: "light.min") { KeyboardBacklight.set(0) },
            PaletteCommand(title: "Pick a color", symbol: "eyedropper") { SystemActions.pickColor() },
            PaletteCommand(title: "Capture an area", symbol: "camera.viewfinder") { SystemActions.captureArea() },
            PaletteCommand(title: "Play / pause music", symbol: "playpause.fill") { MusicService.shared.playPause() },
            PaletteCommand(title: "Camera mirror", symbol: "video.fill") { CameraMirror.shared.toggle() },
            PaletteCommand(title: "Lock keyboard to clean it (60 s, ⌘⎋ unlocks)", symbol: "keyboard") { CleaningLock.shared.startKeyboardLock() },
            PaletteCommand(title: "Black out screens to clean them", symbol: "display") { CleaningLock.shared.startScreenBlackout() },
            PaletteCommand(title: "Floating player", symbol: "music.note.tv") { FloatingPlayer.shared.toggle() },
            PaletteCommand(title: "Full-screen lyrics", symbol: "text.quote") { LyricsScreen.shared.show() },
            PaletteCommand(title: "Paste next from the copy stack", symbol: "square.stack") { CopyStackStore.shared.pasteNext() },
            PaletteCommand(title: "Clear the copy stack", symbol: "square.stack.3d.up.slash") { CopyStackStore.shared.clear() },
            PaletteCommand(title: "Ask about screen", symbol: "text.viewfinder") { AskAboutScreen.start() },
            PaletteCommand(title: WindowWatch.shared.watching ? "Stop watching the screen area" : "Watch a screen area", symbol: "eye") { WindowWatch.shared.watching ? WindowWatch.shared.stop() : WindowWatch.shared.choose() },
            PaletteCommand(title: ScreenRecorder.shared.recording ? "Stop screen recording" : "Record the screen", symbol: "record.circle") { ScreenRecorder.shared.toggle() },
            PaletteCommand(title: "Record an area of the screen", symbol: "rectangle.dashed.badge.record") { ScreenRecorder.shared.recordArea() },
            PaletteCommand(title: "Read QR code on screen", symbol: "qrcode.viewfinder") { QRReader.scanScreen() },
            PaletteCommand(title: "Open teleprompter", symbol: "text.alignleft") { Teleprompter.shared.show() },
            PaletteCommand(title: DictationService.shared.active ? "Stop dictation" : "Dictate", symbol: "mic.fill") { DictationService.shared.toggle() },
            PaletteCommand(title: "Activity today", symbol: "chart.bar.fill") { ActivityCounter.shared.showToday() },
            PaletteCommand(title: AmbientNoise.shared.playing ? "Stop the ambient sound" : "Play ambient sound", symbol: "speaker.wave.2") { AmbientNoise.shared.toggle() },
            PaletteCommand(title: "Rest your eyes (20 s)", symbol: "eye") { EyeBreaks.shared.begin() },
            PaletteCommand(title: "Settings", symbol: "gearshape") { SettingsWindow.show() },
        ]
        if AppVolumeService.supported { list.append(PaletteCommand(title: "App volume", symbol: "slider.horizontal.3") { AppVolumeService.shared.show() }) }
        list += QuickActionsStore.shared.actions.map { a in PaletteCommand(localized: localized("Action: %@", a.name), symbol: "bolt.circle") { QuickActionsStore.shared.run(a) } }
        list += AudioControl.outputDevices().map { d in PaletteCommand(localized: localized("Sound output: %@", d.name), symbol: "hifispeaker.fill") { AudioControl.shared.selectOutput(d) } }
        list += ShortcutsService.shared.names.map { n in PaletteCommand(localized: localized("Shortcut: %@", n), symbol: "bolt.fill") { ShortcutsService.shared.run(n) } }
        list += SnapZone.allCases.map { z in PaletteCommand(localized: localized("Snap window: %@", localized(z.rawValue)), symbol: "rectangle.split.2x1") { WindowSnap.snap(z) } }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return list + CalcStore.history.entries.prefix(5).map { e in PaletteCommand(localized: e, symbol: "clock.arrow.circlepath") { Pasteboard.copy(CalcHistory.result(of: e)) } }
        }
        var out = list.filter { $0.title.localizedCaseInsensitiveContains(q) }
        out += ClipboardService.shared.items.filter { $0.searchable.localizedCaseInsensitiveContains(q) }.prefix(5).map { item in
            PaletteCommand(localized: localized("Paste: %@", String((item.text ?? item.ocr ?? localized("Image")).prefix(50))), symbol: "doc.on.clipboard") { ClipboardService.shared.paste(item) }
        }
        out += SnippetsStore.shared.snippets.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(5).map { sn in
            PaletteCommand(localized: localized("Snippet: %@", sn.name), symbol: "text.quote") { SnippetsStore.shared.paste(sn) }
        }
        if let v = Self.evaluate(q) {
            out.insert(PaletteCommand(localized: "= \(v)  (" + localized("copy") + ")", symbol: "equal.circle") {
                Pasteboard.copy(v)
                CalcStore.record(q, v)
            }, at: 0)
        }
        if let t = QuickCapture.argument(q, keywords: ["event", "ev"]) {
            let (title, due) = RemindersService.parse(t)
            out.insert(PaletteCommand(localized: localized("Add event: %@", title) + (due.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""), symbol: "calendar.badge.plus") {
                CalendarService.shared.addEvent(title: title, start: due)
            }, at: 0)
        }
        if let t = QuickCapture.argument(q, keywords: ["note", "n"]) {
            out.insert(PaletteCommand(localized: localized("Save to Apple Notes: %@", String(t.prefix(40))), symbol: "note.text.badge.plus") { QuickCapture.addNote(t) }, at: 0)
        }
        if Self.evaluate(q) == nil, QuickCapture.argument(q, keywords: ["event", "ev", "note", "n"]) == nil, let r = WebSearch.resolve(q, defaultKey: UserDefaults.standard.string(forKey: "searchEngine") ?? "google") {
            out.append(PaletteCommand(localized: localized("Search %@: %@", localized(r.label), q), symbol: r.label == TranslateRoute.label ? "character.bubble" : "magnifyingglass") {
                NotchModel.shared.collapse(); NSWorkspace.shared.open(r.url)
            })
        }
        return out
    }

    /// Quick math: only digits, operators, dots and parentheses are accepted, and a small parser (not NSExpression,
    /// which raises an exception on "5+" or "(2" and would crash the app while typing) evaluates them.
    static func evaluate(_ s: String) -> String? {
        guard s.range(of: #"^[0-9+\-*/().% ]+$"#, options: .regularExpression) != nil,
              s.contains(where: { "+-*/%".contains($0) }),
              s.range(of: #"[0-9.)] +[0-9.(]"#, options: .regularExpression) == nil else { return nil }
        var p = MathParser(Array(s.filter { $0 != " " }))
        guard let v = p.parse(), v.isFinite else { return nil }
        return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%.6g", v)
    }
}

struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    let close: () -> Void
    @FocusState private var focus: Bool

    var body: some View {
        let cmds = model.commands
        VStack(spacing: 0) {
            TextField("Type a command, search the clipboard, or do math…", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 18)).padding(14).focused($focus)
                .onSubmit { run(cmds) }
                .onChange(of: model.query) { _, _ in model.selection = 0 }
                .onKeyPress(.downArrow) { model.selection = min(model.selection + 1, cmds.count - 1); return .handled }
                .onKeyPress(.upArrow) { model.selection = max(model.selection - 1, 0); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(cmds.enumerated()), id: \.element.id) { i, c in
                        HStack { Image(systemName: c.symbol).frame(width: 22); Text(c.title).lineLimit(1); Spacer() }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(i == model.selection ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle()).onTapGesture { model.selection = i; run(cmds) }
                    }
                }.padding(6)
            }
        }
        .frame(width: 560, height: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .onAppear { focus = true }
    }

    private func run(_ cmds: [PaletteCommand]) {
        guard cmds.indices.contains(model.selection) else { return }
        let c = cmds[model.selection]
        close(); c.run()
    }
}

/// Search that goes to a translation page. WebSearch names its result with `label` and reads the `prefix` ("tr text").
enum TranslateRoute {
    static let label = "Translate"
    static let prefix = "tr"
}

@MainActor
final class PaletteController {
    static let shared = PaletteController()
    /// The palette's window size; the view is drawn at the same size.
    static let size = NSSize(width: 560, height: 360)
    private var panel: NSPanel?
    private let model = PaletteModel()

    func toggle() { panel?.isVisible == true ? hide() : show() }

    func show() {
        model.query = ""; model.selection = 0; model.refresh()
        let p = panel ?? {
            let p = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.styleAsOverlay(level: .floating)
            p.contentView = NSHostingView(rootView: PaletteView(model: model) { [weak self] in self?.hide() })
            panel = p; return p
        }()
        if let s = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: s.frame.midX - Self.size.width / 2, y: s.frame.midY + 120))
        }
        p.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}
