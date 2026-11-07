import AppKit
import SwiftUI
import SwiftTerm

/// One login shell in a PTY that keeps running while you switch tabs. It restarts if the shell exits.
@MainActor
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalSession()
    let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 240))

    override init() {
        super.init()
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = NSColor(white: 0.04, alpha: 1)
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        startShell()
    }

    private func startShell() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("PILLBOX=1")
        view.startProcess(executable: shell, args: ["-l"], environment: env, execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: NSHomeDirectory())
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.startShell() } }
    }
}

struct TerminalTab: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = TerminalSession.shared.view
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}
