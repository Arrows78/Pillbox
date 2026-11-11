import AppKit
import SwiftUI
import SwiftTerm

/// Text size and colors of the Terminal tab. Every session reads them when it starts, and again when they change.
enum TerminalLook {
    static let fontSizes = 10...18
    static let defaultFontSize = 12

    static func clampedSize(_ size: Int) -> Int { min(max(size, fontSizes.lowerBound), fontSizes.upperBound) }
    static var fontSize: Int { clampedSize(Preferences.terminalFontSize.value) }
    static var theme: TerminalTheme { TerminalTheme(rawValue: Preferences.terminalTheme.value) ?? .dark }
}

enum TerminalTheme: String, CaseIterable {
    case dark, light

    var background: NSColor { self == .dark ? NSColor(white: 0.04, alpha: 1) : NSColor(white: 0.98, alpha: 1) }
    var foreground: NSColor { self == .dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.1, alpha: 1) }
}

/// One login shell in a PTY that keeps running while you switch sessions. It restarts if the shell exits, unless it was closed.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    /// Shown as "Session N". Numbers are not reused within one run of the app.
    let number: Int
    let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))
    private(set) var isClosed = false
    private var lastStart = Date.distantPast
    private var quickExits = 0

    init(number: Int) {
        self.number = number
        super.init()
        view.processDelegate = self
        applyLook()
        startShell()
    }

    func applyLook() {
        view.font = NSFont.monospacedSystemFont(ofSize: CGFloat(TerminalLook.fontSize), weight: .regular)
        view.nativeBackgroundColor = TerminalLook.theme.background
        view.nativeForegroundColor = TerminalLook.theme.foreground
    }

    private func startShell() {
        lastStart = Date()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // The shell starts in the home folder whatever Pillbox itself inherited: a working directory, project or
        // previous-directory variable from the launching process must not send it elsewhere.
        var env = Self.sanitized(Terminal.getEnvironmentVariables(termName: "xterm-256color"), home: NSHomeDirectory())
        env.append("PILLBOX=1")
        view.startProcess(executable: shell, args: ["-l"], environment: env, execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: NSHomeDirectory())
    }

    /// The folder the shell is in now, read from the kernel. The home folder once the shell has gone.
    var workingDirectory: String {
        Self.workingDirectory(ofPid: view.process.shellPid) ?? NSHomeDirectory()
    }

    /// Ends the shell. The session is then dropped by TerminalSessions and does not restart.
    func close() {
        isClosed = true
        view.terminate()
        view.removeFromSuperview()
    }

    nonisolated static func sanitized(_ env: [String], home: String) -> [String] {
        let dropped = ["PWD=", "OLDPWD=", "INIT_CWD=", "CLAUDE_PROJECT_DIR=", "CLAUDE_WORKING_DIR="]
        return env.filter { e in !dropped.contains { e.hasPrefix($0) } } + ["PWD=" + home]
    }

    /// The working directory of a process, or nil when the process is gone.
    nonisolated static func workingDirectory(ofPid pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
    }

    /// Opens a folder in Terminal.app, which starts a new window there.
    static func openInTerminalApp(folder: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.shellExited() } }
    }

    /// A shell that dies right after it starts (bad startup file or SHELL) would respawn in a tight loop: give up after a few.
    private func shellExited() {
        guard !isClosed else { return }
        quickExits = Date().timeIntervalSince(lastStart) < 3 ? quickExits + 1 : 0
        guard quickExits < 3 else {
            NotchModel.shared.show(Activity(symbol: "terminal", title: localized("The shell keeps exiting"), subtitle: localized("Check your shell's startup files"), tint: .orange, duration: 5))
            return
        }
        startShell()
    }
}

/// The Terminal tab's sessions, in the order they were opened, with the one on screen.
@MainActor
final class TerminalSessions: ObservableObject {
    private static var instance: TerminalSessions?

    /// The sessions, created the first time the Terminal tab needs them: no shell starts before that.
    static var shared: TerminalSessions {
        if let instance { return instance }
        let made = TerminalSessions()
        instance = made
        return made
    }

    /// Applies the look to the open sessions. Does nothing, and starts no shell, before the Terminal tab was opened.
    static func lookChanged() { instance?.applyLook() }

    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var selectedID: UUID?
    private var nextNumber = 1

    private init() { add() }

    var selected: TerminalSession? { sessions.first { $0.id == selectedID } ?? sessions.first }

    func add() {
        let session = TerminalSession(number: nextNumber)
        nextNumber += 1
        sessions.append(session)
        selectedID = session.id
    }

    func select(_ id: UUID) {
        if sessions.contains(where: { $0.id == id }) { selectedID = id }
    }

    /// Ends the session's shell and removes it. Closing the last one starts a fresh one, so the tab always has a shell.
    func close(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let order = sessions.map(\.id)
        sessions[index].close()
        sessions.remove(at: index)
        guard !sessions.isEmpty else { add(); return }
        selectedID = Self.selectionAfterClosing(order: order, closed: id, selected: selectedID ?? id)
    }

    /// The session to show once `closed` is gone: the one still selected, or else the one that took the closed session's place.
    nonisolated static func selectionAfterClosing(order: [UUID], closed: UUID, selected: UUID) -> UUID? {
        guard let index = order.firstIndex(of: closed) else { return selected }
        var rest = order
        rest.remove(at: index)
        guard !rest.isEmpty else { return nil }
        if closed != selected && rest.contains(selected) { return selected }
        return rest[min(index, rest.count - 1)]
    }

    private func applyLook() {
        for session in sessions { session.applyLook() }
    }
}

/// The Terminal tab: a row of sessions with add and close, then the selected session's terminal.
struct TerminalTab: View {
    @ObservedObject var store = TerminalSessions.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.sessions, id: \.id) { session in sessionChip(session) }
                        Button { store.add() } label: { Image(systemName: "plus").font(Design.captionStrong).frame(width: 22, height: 20) }
                            .buttonStyle(.plain).help(localized("New terminal session"))
                    }
                }
                Spacer(minLength: 8)
                Button("Open in Terminal.app") {
                    if let session = store.selected { TerminalSession.openInTerminalApp(folder: session.workingDirectory) }
                }
                .buttonStyle(.plain).font(Design.label).foregroundStyle(.white.opacity(0.8))
            }
            TerminalHost(view: store.selected?.view)
                .clipShape(RoundedRectangle(cornerRadius: Design.rowRadius))
        }
    }

    private func sessionChip(_ session: TerminalSession) -> some View {
        let selected = session.id == store.selectedID
        return HStack(spacing: 5) {
            Text(localized("Session %lld", session.number)).font(.system(size: 11, weight: selected ? .semibold : .regular))
            if store.sessions.count > 1 {
                Button { store.close(session.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 14) }
                    .buttonStyle(.plain).help(localized("Close this session"))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Design.chipRadius).fill(Color.white.opacity(selected ? 0.18 : 0.06)))
        .contentShape(Rectangle())
        .onTapGesture { store.select(session.id) }
    }
}

/// Puts the selected session's terminal view in place. The views live in their sessions, so switching only moves them.
struct TerminalHost: NSViewRepresentable {
    let view: LocalProcessTerminalView?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let view, container.subviews.first !== view else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}
