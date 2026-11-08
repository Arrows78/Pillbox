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
        self.title = L(title); self.symbol = symbol; self.run = run
    }
    init(localized title: String, symbol: String, run: @escaping @MainActor () -> Void) {
        self.title = title; self.symbol = symbol; self.run = run
    }
}

@MainActor
final class PaletteModel: ObservableObject {
    @Published var query = ""
    @Published var selection = 0

    var commands: [PaletteCommand] {
        let m = NotchModel.shared, t = TimerService.shared
        var list = Tab.allCases.enumerated().map { i, tab in
            PaletteCommand(localized: L("Go to %@", tab.title) + (i < 9 ? "  ⌘\(i + 1)" : ""), symbol: tab.symbol) { m.expand(tab) }
        }
        list += [
            PaletteCommand(title: CaffeineService.shared.active ? "Turn keep awake off" : "Turn keep awake on", symbol: "cup.and.saucer.fill") { CaffeineService.shared.toggle() },
            PaletteCommand(title: "Start focus session", symbol: "timer") { t.mode = .focus; t.start() },
            PaletteCommand(title: "Start stopwatch", symbol: "stopwatch") { t.mode = .stopwatch; t.start() },
            PaletteCommand(title: AudioControl.shared.micMuted ? "Unmute microphone" : "Mute microphone", symbol: "mic.slash.fill") { AudioControl.shared.toggleMic() },
            PaletteCommand(title: "Pick a color", symbol: "eyedropper") { Tools.pickColor() },
            PaletteCommand(title: "Capture an area", symbol: "camera.viewfinder") { Tools.captureArea() },
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
            PaletteCommand(title: "Open teleprompter", symbol: "text.alignleft") { Teleprompter.shared.show() },
            PaletteCommand(title: "Settings", symbol: "gearshape") { SettingsWindow.show() },
        ]
        list += QuickActionsStore.shared.actions.map { a in PaletteCommand(localized: L("Action: %@", a.name), symbol: "bolt.circle") { QuickActionsStore.shared.run(a) } }
        list += AudioControl.outputDevices().map { d in PaletteCommand(localized: L("Sound output: %@", d.name), symbol: "hifispeaker.fill") { AudioControl.shared.selectOutput(d) } }
        list += ShortcutsService.shared.names.map { n in PaletteCommand(localized: L("Shortcut: %@", n), symbol: "bolt.fill") { ShortcutsService.shared.run(n) } }
        list += SnapZone.allCases.map { z in PaletteCommand(localized: L("Snap window: %@", L(z.rawValue)), symbol: "rectangle.split.2x1") { WindowSnap.snap(z) } }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            return list + CalcStore.history.entries.prefix(5).map { e in PaletteCommand(localized: e, symbol: "clock.arrow.circlepath") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(CalcHistory.result(of: e), forType: .string) } }
        }
        var out = list.filter { $0.title.localizedCaseInsensitiveContains(q) }
        out += ClipboardService.shared.items.filter { $0.searchable.localizedCaseInsensitiveContains(q) }.prefix(5).map { item in
            PaletteCommand(localized: L("Paste: %@", String((item.text ?? item.ocr ?? L("Image")).prefix(50))), symbol: "doc.on.clipboard") { ClipboardService.shared.paste(item) }
        }
        out += SnippetsStore.shared.snippets.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(5).map { sn in
            PaletteCommand(localized: L("Snippet: %@", sn.name), symbol: "text.quote") { SnippetsStore.shared.paste(sn) }
        }
        if let v = Self.evaluate(q) {
            out.insert(PaletteCommand(localized: "= \(v)  (" + L("copy") + ")", symbol: "equal.circle") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(v, forType: .string)
                CalcStore.record(q, v)
            }, at: 0)
        }
        if let t = QuickCapture.argument(q, keywords: ["event", "ev"]) {
            let (title, due) = RemindersService.parse(t)
            out.insert(PaletteCommand(localized: L("Add event: %@", title) + (due.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""), symbol: "calendar.badge.plus") {
                CalendarService.shared.addEvent(title: title, start: due)
            }, at: 0)
        }
        if let t = QuickCapture.argument(q, keywords: ["note", "n"]) {
            out.insert(PaletteCommand(localized: L("Save to Apple Notes: %@", String(t.prefix(40))), symbol: "note.text.badge.plus") { QuickCapture.addNote(t) }, at: 0)
        }
        if Self.evaluate(q) == nil, QuickCapture.argument(q, keywords: ["event", "ev", "note", "n"]) == nil, let r = WebSearch.resolve(q, defaultKey: UserDefaults.standard.string(forKey: "searchEngine") ?? "google") {
            out.append(PaletteCommand(localized: L("Search %@: %@", L(r.label), q), symbol: r.label == "Translate" ? "character.bubble" : "magnifyingglass") {
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

/// Recursive-descent evaluator: `+ - * /`, unary minus, parentheses and a trailing `%` (which divides by 100,
/// at the precedence of `*` and `/`). Returns nil for anything malformed.
struct MathParser {
    private let chars: [Character]
    private var i = 0
    init(_ chars: [Character]) { self.chars = chars }

    mutating func parse() -> Double? {
        guard let v = expression(), i == chars.count else { return nil }
        return v
    }

    private mutating func expression() -> Double? {
        guard var v = term() else { return nil }
        while i < chars.count, chars[i] == "+" || chars[i] == "-" {
            let op = chars[i]; i += 1
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = factor() else { return nil }
        while i < chars.count, "*/%".contains(chars[i]) {
            let op = chars[i]; i += 1
            if op == "%" { v /= 100; continue }
            guard let r = factor() else { return nil }
            v = op == "*" ? v * r : v / r
        }
        return v
    }

    private mutating func factor() -> Double? {
        guard i < chars.count else { return nil }
        if chars[i] == "-" { i += 1; return factor().map { -$0 } }
        if chars[i] == "(" {
            i += 1
            guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
            i += 1; return v
        }
        let start = i
        while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
        return start < i ? Double(String(chars[start..<i])) : nil
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
                .onChange(of: model.query) { _ in model.selection = 0 }
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

@MainActor
final class PaletteController {
    static let shared = PaletteController()
    private var panel: NSPanel?
    private let model = PaletteModel()

    func toggle() { panel?.isVisible == true ? hide() : show() }

    func show() {
        model.query = ""; model.selection = 0
        let p = panel ?? {
            let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating; p.hasShadow = true
            p.contentView = NSHostingView(rootView: PaletteView(model: model) { [weak self] in self?.hide() })
            panel = p; return p
        }()
        if let s = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: s.frame.midX - 280, y: s.frame.midY + 120))
        }
        p.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

/// The app's global shortcuts. They are registered at launch and listed in Settings from this one table,
/// so the Shortcuts page can never show a key that does nothing.
enum GlobalShortcut: UInt32, CaseIterable {
    case palette = 1, toggleNotch, pasteNext

    /// English text of the action (a localisation key).
    var title: String {
        switch self {
        case .palette: "Command palette"
        case .toggleNotch: "Toggle Notch"
        case .pasteNext: "Paste next from the copy stack"
        }
    }

    var key: String {
        switch self { case .palette: "K"; case .toggleNotch: "N"; case .pasteNext: "V" }
    }

    var keyCode: UInt32 {
        switch self { case .palette: UInt32(kVK_ANSI_K); case .toggleNotch: UInt32(kVK_ANSI_N); case .pasteNext: UInt32(kVK_ANSI_V) }
    }

    static let modifiers = UInt32(controlKey | optionKey)
    var keycaps: String { "⌃⌥" + key }

    @MainActor func run() {
        switch self {
        case .palette: PaletteController.shared.toggle()
        case .toggleNotch: NotchModel.shared.toggle()
        case .pasteNext: CopyStackStore.shared.pasteNext()
        }
    }
}

/// Carbon global hotkey (works without any privacy permission).
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        if !Self.installed {
            Self.installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        Self.handlers[id] = handler
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x50424F58), id: id), GetApplicationEventTarget(), 0, &ref)
    }
}
