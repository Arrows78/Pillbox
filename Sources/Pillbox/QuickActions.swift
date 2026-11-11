import Foundation
import AppKit
import SwiftUI
import WebKit

enum PillAction: String, CaseIterable, Identifiable {
    case none, playPause, keepAwake, palette, clipboard, shelf, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: localized("Nothing"); case .playPause: localized("Play / pause music"); case .keepAwake: localized("Toggle keep awake")
        case .palette: localized("Command palette"); case .clipboard: localized("Open the clipboard"); case .shelf: localized("Open the shelf"); case .settings: localized("Settings")
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
    /// Taps in a row. One tap gesture counts them, so a triple click does not also fire the double-click action.
    @State private var taps = 0

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture {
                taps += 1
                let count = taps
                Task { @MainActor in
                    // The run of taps ends once a double-click interval passes without another tap.
                    try? await Task.sleep(nanoseconds: UInt64(NSEvent.doubleClickInterval * 1_000_000_000))
                    guard taps == count else { return }
                    taps = 0
                    if count == 2 { PillAction.configured("doubleClickAction").run() }
                    else if count >= 3 { PillAction.configured("tripleClickAction").run() }
                }
            }
            .contextMenu {
                if ScreenRecorder.shared.recording { Button("Stop recording") { ScreenRecorder.shared.stop() } }
                ForEach(PillAction.allCases.filter { $0 == .palette || $0 == .keepAwake || $0 == .playPause }) { a in
                    Button(a.title) { a.run() }
                }
                Divider()
                Button(PillAction.settings.title) { PillAction.settings.run() }
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
    /// URL schemes for web apps, and for plain links (which also allow mail and phone).
    static let webSchemes: Set<String> = ["http", "https"]
    static let linkSchemes = webSchemes.union(["mailto", "tel"])

    /// Runs a command with the login shell; stopped after `timeout` (status 124, like coreutils `timeout`).
    nonisolated static func runShell(_ command: String, timeout: TimeInterval = 15) -> (status: Int32, output: String) {
        let r = ProcessRunner.run("/bin/zsh", ["-c", command], timeout: timeout)
        return (r.status, r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Only plain web and mail links: never `file:` or `javascript:`.
    nonisolated static func url(_ s: String, allowed: Set<String> = ActionRunner.linkSchemes) -> URL? {
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
        if kind != .shell, ActionRunner.url(v, allowed: kind == .web ? ActionRunner.webSchemes : ActionRunner.linkSchemes) == nil { return false }
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
                                                        subtitle: r.status == 0 ? String(r.output.suffix(80)) : localized("Failed (status %d)", Int(r.status)),
                                                        tint: r.status == 0 ? .green : .red, duration: 4))
                    }
                }
            }
        case .url: if let u = ActionRunner.url(a.value) { NotchModel.shared.collapse(); NSWorkspace.shared.open(u) }
        case .web: if let u = ActionRunner.url(a.value, allowed: ActionRunner.webSchemes) { WebApps.open(name: a.name, url: u) }
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

// MARK: Copying text

/// Puts plain text on the general pasteboard.
enum TextCopy {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: Notification island (needs Full Disk Access)
