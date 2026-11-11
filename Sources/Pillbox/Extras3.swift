import AppKit
import SwiftUI
import WebKit

// MARK: Activity queue

/// Islands arrive faster than they can be read: later ones wait their turn, an update of the one on screen
/// (same symbol and title, e.g. a volume bar) replaces it in place, and the backlog is capped.
struct ActivityQueue {
    private(set) var current: Activity?
    private(set) var pending: [Activity] = []
    static let cap = 4

    private static func same(_ a: Activity, _ b: Activity) -> Bool { a.title == b.title && a.symbol == b.symbol }

    /// True when the visible island changed. Importance decides the order: a high one jumps the queue and replaces a HUD
    /// on screen, a low one (volume, caps lock) is dropped when something else is showing rather than shown late.
    mutating func push(_ a: Activity) -> Bool {
        guard let c = current else { current = a; return true }
        if Self.same(c, a) { current = a; return true }
        if let i = pending.firstIndex(where: { Self.same($0, a) }) { pending[i] = a; return false }
        switch a.priority {
        case .low: return false
        case .high:
            if c.priority == .low { current = a; return true }
            pending.insert(a, at: 0)
            if pending.count > Self.cap { pending.remove(at: 1) }   // the oldest of the others goes
        case .normal:
            pending.append(a)
            if pending.count > Self.cap { pending.removeFirst() }   // the newest are kept
        }
        return false
    }

    mutating func advance() { current = pending.isEmpty ? nil : pending.removeFirst() }
    mutating func clear() { current = nil; pending = [] }
}

// MARK: Island theme

enum IslandTheme: String, CaseIterable, Identifiable {
    case black, graphite, glass, accent
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    static var current: IslandTheme { IslandTheme(rawValue: UserDefaults.standard.string(forKey: "islandTheme") ?? "black") ?? .black }
}

/// The collapsed pill is always black so it melts into the notch; the open panel follows the theme.
struct IslandBackground: View {
    let expanded: Bool
    @AppStorage("islandTheme") private var theme = "black"

    var body: some View {
        let r: CGFloat = expanded ? 28 : 12
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
        ZStack {
            if expanded && theme == "glass" {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.4))
            } else {
                shape.fill(.black)
                if expanded && theme == "graphite" { shape.fill(Color.white.opacity(0.10)) }
                if expanded && theme == "accent" { shape.fill(Color.accentColor.opacity(0.30)) }
            }
        }
        .overlay {
            // A faint lit edge gives the open panel some depth against dark wallpapers.
            if expanded { shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5) }
        }
    }
}

// MARK: Gestures on the pill

enum PillAction: String, CaseIterable, Identifiable {
    case none, playPause, keepAwake, palette, clipboard, shelf, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: L("Nothing"); case .playPause: L("Play / pause music"); case .keepAwake: L("Toggle keep awake")
        case .palette: L("Command palette"); case .clipboard: L("Open the clipboard"); case .shelf: L("Open the shelf"); case .settings: L("Settings")
        }
    }

    static func configured(_ key: String) -> PillAction { PillAction(rawValue: UserDefaults.standard.string(forKey: key) ?? "none") ?? .none }

    @MainActor func run() {
        switch self {
        case .none: break
        case .playPause: MusicService.shared.playPause()
        case .keepAwake: CaffeineService.shared.toggle()
        case .palette: PaletteController.shared.toggle()
        case .clipboard: NotchModel.shared.expand(.clipboard)
        case .shelf: NotchModel.shared.expand(.shelf)
        case .settings: SettingsWindow.show()
        }
    }
}

/// Invisible layer over the collapsed pill: double and triple clicks run the configured actions, right click opens a menu.
struct PillGestures: View {
    var body: some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(count: 3) { PillAction.configured("tripleClickAction").run() }
            .onTapGesture(count: 2) { PillAction.configured("doubleClickAction").run() }
            .contextMenu {
                if ScreenRecorder.shared.recording { Button("Stop recording") { ScreenRecorder.shared.stop() } }
                Button("Command palette") { PaletteController.shared.toggle() }
                Button("Toggle keep awake") { CaffeineService.shared.toggle() }
                Button("Play / pause music") { MusicService.shared.playPause() }
                Divider()
                Button("Settings") { SettingsWindow.show() }
                Button("Quit Pillbox") { NSApp.terminate(nil) }
            }
    }
}

// MARK: Quick actions and web mini-apps

struct QuickAction: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable { case shell, url, web; var id: String { rawValue } }
    var id = UUID()
    var name: String
    var kind: Kind
    var value: String
}

enum ActionRunner {
    /// Runs a command with the login shell; killed after `timeout` (status 124, like coreutils `timeout`).
    nonisolated static func runShell(_ command: String, timeout: TimeInterval = 15) -> (status: Int32, output: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = ["-c", command]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return (127, "") }
        var timedOut = false
        let kill = DispatchWorkItem { timedOut = true; p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); kill.cancel()
        return (timedOut ? 124 : p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Only plain web and mail links: never `file:` or `javascript:`.
    nonisolated static func url(_ s: String, allowed: Set<String> = ["http", "https", "mailto", "tel"]) -> URL? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t.contains("://") || t.hasPrefix("mailto:") || t.hasPrefix("tel:") ? t : "https://" + t),
              let scheme = u.scheme?.lowercased(), allowed.contains(scheme) else { return nil }
        return u
    }
}

@MainActor
final class QuickActionsStore: ObservableObject {
    static let shared = QuickActionsStore()
    @Published var actions: [QuickAction] = Store.load("actions.json", as: [QuickAction].self) ?? []

    func add(name: String, kind: QuickAction.Kind, value: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespaces), v = value.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !v.isEmpty else { return false }
        if kind != .shell, ActionRunner.url(v, allowed: kind == .web ? ["http", "https"] : ["http", "https", "mailto", "tel"]) == nil { return false }
        actions.append(QuickAction(name: n, kind: kind, value: v)); save(); return true
    }

    func remove(_ a: QuickAction) { actions.removeAll { $0.id == a.id }; save() }
    private func save() { Store.save(actions, "actions.json") }

    func run(_ a: QuickAction) {
        switch a.kind {
        case .shell:
            NotchModel.shared.collapse()
            DispatchQueue.global(qos: .userInitiated).async {
                let r = ActionRunner.runShell(a.value)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        NotchModel.shared.show(Activity(symbol: r.status == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill", title: a.name,
                                                        subtitle: r.status == 0 ? String(r.output.suffix(80)) : L("Failed (status %d)", Int(r.status)),
                                                        tint: r.status == 0 ? .green : .red, duration: 4))
                    }
                }
            }
        case .url: if let u = ActionRunner.url(a.value) { NotchModel.shared.collapse(); NSWorkspace.shared.open(u) }
        case .web: if let u = ActionRunner.url(a.value, allowed: ["http", "https"]) { WebApps.open(name: a.name, url: u) }
        }
    }
}

@MainActor
enum WebApps {
    private static var windows: [String: NSWindow] = [:]

    static func open(name: String, url: URL) {
        NotchModel.shared.collapse()
        let key = url.absoluteString
        if let w = windows[key], w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        web.load(URLRequest(url: url))
        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = name; w.contentView = web; w.isReleasedWhenClosed = false; w.center()
        windows[key] = w
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct ActionsGrid: View {
    @ObservedObject var store = QuickActionsStore.shared
    var body: some View {
        ScrollView {
            if store.actions.isEmpty { Text("Add shell commands, links and web mini-apps in Settings › Quick actions").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                ForEach(store.actions) { a in
                    Button { store.run(a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.kind == .shell ? "terminal" : a.kind == .web ? "macwindow" : "link").foregroundStyle(.orange)
                            Text(verbatim: a.name).lineLimit(1)
                        }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).contextMenu { Button("Remove") { store.remove(a) } }
                }
            }
        }
    }
}

struct QuickActionsEditor: View {
    @ObservedObject var store = QuickActionsStore.shared
    @State private var name = ""
    @State private var kind = QuickAction.Kind.shell
    @State private var value = ""
    @State private var invalid = false

    var body: some View {
        ForEach(store.actions) { a in
            HStack { Text(verbatim: "\(a.name)  ·  \(a.value)").lineLimit(1).font(.caption); Spacer(); Button("Remove") { store.remove(a) }.controlSize(.small) }
        }
        HStack {
            TextField("Name", text: $name)
            Picker("", selection: $kind) { Text("Command").tag(QuickAction.Kind.shell); Text("Link").tag(QuickAction.Kind.url); Text("Web app").tag(QuickAction.Kind.web) }.labelsHidden().frame(width: 110)
        }
        TextField(kind == .shell ? "Shell command, e.g. open -a Safari" : "https://…", text: $value)
        HStack {
            Button("Add action") { invalid = !store.add(name: name, kind: kind, value: value); if !invalid { name = ""; value = "" } }.controlSize(.small)
            if invalid { Text("Check the name and the link").font(.caption).foregroundStyle(.orange) }
        }
    }
}

// MARK: Notification island (opt-in, needs Full Disk Access)

/// New Notification Center entries shown as islands, with the app's own wording.
@MainActor
final class NotificationFeed {
    static let shared = NotificationFeed()
    private var lastID: Int64?
    private var timer: Timer?

    nonisolated static let codeKey = "codeIsland"

    /// Items newer than `after`, oldest first.
    nonisolated static func fresh(_ items: [NotificationItem], after: Int64) -> [NotificationItem] {
        items.filter { $0.id > after }.sorted { $0.id < $1.id }
    }

    /// A 4 to 8 digit verification code in a message, when the text talks about a code (or is nothing but the code).
    nonisolated static func verificationCode(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil { return t }
        let keywords = ["code", "verification", "verify", "otp", "passcode", "pin", "2fa", "one-time", "mot de passe", "código", "codice"]
        guard keywords.contains(where: { t.lowercased().contains($0) }) else { return nil }
        guard let r = t.range(of: #"(?<![\d.,])\d{3}[ -]?\d{3}(?![\d.,])|(?<![\d.,])\d{4,8}(?![\d.,])"#, options: .regularExpression) else { return nil }
        return t[r].filter(\.isNumber)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            let codes = UserDefaults.standard.object(forKey: Self.codeKey) as? Bool ?? true
            guard UserDefaults.standard.bool(forKey: "notificationIsland") || codes else { self?.lastID = nil; return }
            DispatchQueue.global(qos: .utility).async {
                let items = NotificationReader.read(limit: 10)
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(items) } }
            }
        }
    }

    private func handle(_ items: [NotificationItem]?) {
        guard let items else { return }
        defer { lastID = max(lastID ?? 0, items.map(\.id).max() ?? 0) }
        guard let last = lastID else { return }   // first read is only a baseline
        let mirror = UserDefaults.standard.bool(forKey: "notificationIsland"), codes = UserDefaults.standard.object(forKey: Self.codeKey) as? Bool ?? true
        for n in Self.fresh(items, after: last).suffix(3) {
            if codes, let code = Self.verificationCode(in: n.body) ?? Self.verificationCode(in: n.title) {
                NotchModel.shared.show(Activity(symbol: "key.fill", title: L("Code %@", code), subtitle: n.title.isEmpty ? n.app : n.title, tint: .green,
                                                actionTitle: "Copy", action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }, duration: 12))
            } else if mirror {
                NotchModel.shared.show(Activity(symbol: "bell.fill", title: n.title.isEmpty ? n.app : n.title, subtitle: n.body.isEmpty ? nil : String(n.body.prefix(90)), tint: .yellow, duration: 5))
            }
        }
    }
}
