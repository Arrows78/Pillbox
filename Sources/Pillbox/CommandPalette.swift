import Foundation
import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Where a command goes in the menu bar's Actions submenu. The palette itself lists them flat.
/// `tabs` is not shown there: the menu has its own Open Tab submenu.
enum PaletteCategory: String, CaseIterable {
    case general = "General", music = "Music and sound", display = "Display", capture = "Capture"
    case windows = "Windows", focus = "Focus", cleaning = "Cleaning", actions = "Shortcuts and actions", tabs = "Tabs"

    var title: String { localized(rawValue) }
}

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    /// The English title that does not change with the state of the command (the "on" or "off" form it shows first).
    /// Aliases are kept by it. Empty for the rows that are not commands (tabs, apps, files, clipboard).
    let key: String
    let symbol: String
    let category: PaletteCategory
    /// The shortcut the row runs, shown on its right ("⌘2", "⌃⌥V"), or nil.
    let shortcut: String?
    let run: @MainActor () -> Void

    /// `title` is an English key, localised here so filtering matches what the user reads.
    init(title: String, symbol: String, category: PaletteCategory = .general, key: String? = nil, shortcut: String? = nil, run: @escaping @MainActor () -> Void) {
        self.title = localized(title); self.key = key ?? title; self.symbol = symbol; self.category = category; self.shortcut = shortcut; self.run = run
    }
    init(localized title: String, symbol: String, category: PaletteCategory = .general, shortcut: String? = nil, run: @escaping @MainActor () -> Void) {
        self.title = title; self.key = ""; self.symbol = symbol; self.category = category; self.shortcut = shortcut; self.run = run
    }
}

@MainActor
final class PaletteModel: ObservableObject {
    /// Changing the query rebuilds the rows; so does opening the palette, so live labels (keep awake, microphone) are current.
    @Published var query = "" { didSet { queryChanged() } }
    @Published var selection = 0
    /// The rows for the current query. Built when the query changes or the palette opens, not on every redraw.
    private(set) var commands: [PaletteCommand] = []
    /// The files Spotlight found for the "f " prefix, once its search has gathered.
    private var fileHits: [URL] = []

    init() { refresh() }

    func refresh() { commands = buildCommands() }

    private func queryChanged() {
        if case .files(let rest) = PalettePrefix(query), !rest.isEmpty {
            fileHits = []
            FileSearch.shared.search(rest) { [weak self] urls in
                guard let self else { return }
                self.fileHits = urls
                self.objectWillChange.send()
                self.refresh()
            }
        } else {
            FileSearch.shared.cancel(); fileHits = []
        }
        refresh()
    }

    /// The commands whose titles, or whose alias, match `query`, best match first. An empty query keeps the order given.
    static func ranked(_ list: [PaletteCommand], _ query: String) -> [PaletteCommand] {
        guard !query.isEmpty else { return list }
        let aliases = Preferences.paletteAliases.value
        return list.compactMap { c in score(query, c, aliases).map { (c, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// The better of the title's score and the alias's score (a little higher, so a typed alias ranks first).
    static func score(_ query: String, _ c: PaletteCommand, _ aliases: [String: String]) -> Int? {
        let title = FuzzyMatch.score(query, in: c.title)
        let alias = aliases[c.key].flatMap { FuzzyMatch.score(query, in: $0) }.map { $0 + 10 }
        return [title, alias].compactMap { $0 }.max()
    }

    /// The shortcut of a global shortcut, when it is on and registered: the palette shows it next to its command.
    static func label(_ s: GlobalShortcut) -> String? {
        s.isEnabled && !HotKey.unavailable.contains(s.rawValue) ? s.keycaps : nil
    }

    private func buildCommands() -> [PaletteCommand] {
        let notch = NotchModel.shared, timers = TimerService.shared
        var list = Tab.visible.enumerated().map { i, tab in
            PaletteCommand(localized: localized("Go to %@", tab.title), symbol: tab.symbol, category: .tabs, shortcut: i < 9 ? "⌘\(i + 1)" : nil) { notch.expand(tab) }
        }
        list += [
            PaletteCommand(title: CaffeineService.shared.active ? "Turn keep awake off" : "Turn keep awake on", symbol: "cup.and.saucer.fill", key: "Turn keep awake on") { CaffeineService.shared.toggle() },
            PaletteCommand(title: "Start focus session", symbol: "timer", category: .focus) { timers.mode = .focus; timers.start() },
            PaletteCommand(title: "Start stopwatch", symbol: "stopwatch", category: .focus) { timers.mode = .stopwatch; timers.start() },
            PaletteCommand(title: AudioControl.shared.micMuted ? "Unmute microphone" : "Mute microphone", symbol: "mic.slash.fill", category: .music, key: "Mute microphone") { AudioControl.shared.toggleMic() },
            PaletteCommand(title: "Video speed 1×", symbol: "speedometer", category: .music) { VideoSpeed.set(1) },
            PaletteCommand(title: "Video speed 1.5×", symbol: "speedometer", category: .music) { VideoSpeed.set(1.5) },
            PaletteCommand(title: "Video speed 2×", symbol: "speedometer", category: .music) { VideoSpeed.set(2) },
            PaletteCommand(title: "Pick a color", symbol: "eyedropper", category: .capture) { SystemActions.pickColor() },
            PaletteCommand(title: "Capture an area", symbol: "camera.viewfinder", category: .capture) { SystemActions.captureArea() },
            PaletteCommand(title: "Play / pause music", symbol: "playpause.fill", category: .music) { MusicService.shared.playPause() },
            PaletteCommand(title: "Camera mirror", symbol: "video.fill", category: .capture) { CameraMirror.shared.toggle() },
            PaletteCommand(title: "Lock keyboard to clean it (60 s, ⌘⎋ unlocks)", symbol: "keyboard", category: .cleaning) { CleaningLock.shared.startKeyboardLock() },
            PaletteCommand(title: "Black out screens to clean them", symbol: "display", category: .cleaning) { CleaningLock.shared.startScreenBlackout() },
            PaletteCommand(title: "Floating player", symbol: "music.note.tv", category: .music) { FloatingPlayer.shared.toggle() },
            PaletteCommand(title: "Full-screen lyrics", symbol: "text.quote", category: .music) { LyricsScreen.shared.show() },
            PaletteCommand(title: "Paste next from the copy stack", symbol: "square.stack", category: .windows, shortcut: Self.label(.pasteNext)) { CopyStackStore.shared.pasteNext() },
            PaletteCommand(title: "Clear the copy stack", symbol: "square.stack.3d.up.slash", category: .windows) { CopyStackStore.shared.clear() },
            PaletteCommand(title: "Ask about screen", symbol: "text.viewfinder", category: .capture) { AskAboutScreen.start() },
            PaletteCommand(title: WindowWatch.shared.watching ? "Stop watching the screen area" : "Watch a screen area", symbol: "eye", category: .capture, key: "Watch a screen area") { WindowWatch.shared.watching ? WindowWatch.shared.stop() : WindowWatch.shared.choose() },
            PaletteCommand(title: ScreenRecorder.shared.recording ? "Stop screen recording" : "Record the screen", symbol: "record.circle", category: .capture, key: "Record the screen") { ScreenRecorder.shared.toggle() },
            PaletteCommand(title: "Record an area of the screen", symbol: "rectangle.dashed.badge.record", category: .capture) { ScreenRecorder.shared.recordArea() },
            PaletteCommand(title: "Read QR code on screen", symbol: "qrcode.viewfinder", category: .capture) { QRReader.scanScreen() },
            PaletteCommand(title: "Open teleprompter", symbol: "text.alignleft", category: .capture) { Teleprompter.shared.show() },
            PaletteCommand(title: DictationService.shared.active ? "Stop dictation" : "Dictate", symbol: "mic.fill", key: "Dictate", shortcut: Self.label(.dictate)) { DictationService.shared.toggle() },
            PaletteCommand(title: "Activity today", symbol: "chart.bar.fill") { ActivityCounter.shared.showToday() },
            PaletteCommand(title: AmbientNoise.shared.playing ? "Stop the ambient sound" : "Play ambient sound", symbol: "speaker.wave.2", category: .focus, key: "Play ambient sound") { AmbientNoise.shared.toggle() },
            PaletteCommand(title: "Rest your eyes (20 s)", symbol: "eye", category: .focus) { EyeBreaks.shared.begin() },
            PaletteCommand(title: "Settings", symbol: "gearshape") { SettingsWindow.show() },
        ]
        // Only what this Mac can do: an external screen to dim, a keyboard with a backlight.
        if ExternalBrightness.hasExternalScreen {
            list += [PaletteCommand(title: "External display brightness up", symbol: "sun.max.fill", category: .display) { ExternalBrightness.step(10) },
                     PaletteCommand(title: "External display brightness down", symbol: "sun.min.fill", category: .display) { ExternalBrightness.step(-10) }]
        }
        if KeyboardBacklight.available {
            list += [PaletteCommand(title: "Keyboard backlight up", symbol: "light.max", category: .display) { KeyboardBacklight.step(0.25) },
                     PaletteCommand(title: "Keyboard backlight down", symbol: "light.min", category: .display) { KeyboardBacklight.step(-0.25) },
                     PaletteCommand(title: "Turn keyboard backlight off", symbol: "light.min", category: .display) { KeyboardBacklight.set(0) }]
        }
        if AppVolumeService.supported { list.append(PaletteCommand(title: "App volume", symbol: "slider.horizontal.3", category: .music) { AppVolumeService.shared.show() }) }
        list += QuickActionsStore.shared.actions.map { a in PaletteCommand(localized: localized("Action: %@", a.name), symbol: "bolt.circle", category: .actions) { QuickActionsStore.shared.run(a) } }
        list += AudioControl.outputDevices().map { d in PaletteCommand(localized: localized("Sound output: %@", d.name), symbol: "hifispeaker.fill", category: .music) { AudioControl.shared.selectOutput(d) } }
        list += ShortcutsService.shared.names.map { n in PaletteCommand(localized: localized("Shortcut: %@", n), symbol: "bolt.fill", category: .actions) { ShortcutsService.shared.run(n) } }
        list += SnapZone.allCases.map { z in PaletteCommand(localized: localized("Snap window: %@", localized(z.rawValue)), symbol: "rectangle.split.2x1", category: .windows) { WindowSnap.snap(z) } }
        let q = query.trimmingCharacters(in: .whitespaces)
        // `>` lists the commands only, `/` the clipboard only, `f ` the files, `w ` the windows; each is ranked by how well it matches.
        switch PalettePrefix(query) {
        case .commands(let rest):
            return Self.ranked(list, rest)
        case .clipboard(let rest):
            return ClipboardService.shared.items.compactMap { item in FuzzyMatch.score(rest, in: item.searchable).map { (item, $0) } }
                .sorted { $0.1 > $1.1 }.prefix(20).map { item, _ in
                    PaletteCommand(localized: localized("Paste: %@", String((item.text ?? item.ocr ?? localized("Image")).prefix(50))), symbol: "doc.on.clipboard") { ClipboardService.shared.paste(item) }
                }
        case .files(let rest):
            return rest.isEmpty ? [] : fileHits.map { url in
                PaletteCommand(localized: url.lastPathComponent, symbol: "doc") { NSWorkspace.shared.open(url) }
            }
        case .windows(let rest):
            return Self.ranked(PaletteWindows.rows(), rest)
        case .none: break
        }
        guard !q.isEmpty else {
            // The commands run most recently come first, then the rest in their usual order.
            let recent = PaletteRecents.titles.compactMap { t in list.first { $0.title == t } }
            let rest = list.filter { c in !recent.contains { $0.title == c.title } }
            return recent + rest + CalcStore.history.entries.prefix(5).map { e in PaletteCommand(localized: e, symbol: "clock.arrow.circlepath") { Pasteboard.copy(CalcHistory.result(of: e)) } }
        }
        var out = Self.ranked(list, q)
        out += PaletteApps.matches(q, in: PaletteApps.installed).map { app in
            PaletteCommand(localized: app.name, symbol: "app.dashed") { NSWorkspace.shared.open(app.url) }
        }
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
        if let v = UnitConverter.answer(q) {
            out.insert(PaletteCommand(localized: "= \(v)  (" + localized("copy") + ")", symbol: "arrow.left.arrow.right") {
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
        if Self.evaluate(q) == nil, UnitConverter.answer(q) == nil, QuickCapture.argument(q, keywords: ["event", "ev", "note", "n"]) == nil, let r = WebSearch.resolve(q, defaultKey: UserDefaults.standard.string(forKey: "searchEngine") ?? "google") {
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
            TextField("Command, app, math, f file or w window…", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 18)).padding(14).focused($focus)
                .onSubmit { run(cmds) }
                .onChange(of: model.query) { _, _ in model.selection = 0 }
                .onKeyPress(.downArrow) { model.selection = min(model.selection + 1, cmds.count - 1); return .handled }
                .onKeyPress(.upArrow) { model.selection = max(model.selection - 1, 0); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                // ⌘1–9 run the row with that number, the first nine rows.
                .onKeyPress(keys: Set((1...9).map { KeyEquivalent(Character(String($0))) })) { press in
                    guard press.modifiers.contains(.command), let n = Int(press.characters), cmds.indices.contains(n - 1) else { return .ignored }
                    model.selection = n - 1
                    run(cmds)
                    return .handled
                }
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(cmds.enumerated()), id: \.element.id) { i, c in
                        HStack {
                            Image(systemName: c.symbol).frame(width: 22)
                            Text(c.title).lineLimit(1)
                            Spacer()
                            if let shortcut = c.shortcut { Keycaps(shortcut).opacity(0.7) }
                        }
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
        PaletteRecents.record(c.title)
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
