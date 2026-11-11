import AppKit
import Foundation

/// Apple Shortcuts through the system `shortcuts` command.
@MainActor
final class ShortcutsService: ObservableObject {
    static let shared = ShortcutsService()
    @Published private(set) var names: [String] = []
    @Published private(set) var running: String?
    private static let tool = "/usr/bin/shortcuts"

    nonisolated static func parseList(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func refresh() {
        guard FileManager.default.isExecutableFile(atPath: Self.tool) else { return }
        DispatchQueue.global(qos: .utility).async {
            let out = Self.exec(["list"]).output
            let list = Self.parseList(out)
            DispatchQueue.main.async { MainActor.assumeIsolated { self.names = list } }
        }
    }

    func run(_ name: String) {
        guard running == nil else { return }
        running = name
        NotchModel.shared.collapse()
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.exec(["run", name], timeout: 120)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.running = nil
                    NotchModel.shared.show(Activity(symbol: r.status == 0 ? "checkmark.circle.fill" : "xmark.octagon.fill", title: name,
                                                    subtitle: r.status == 0 ? "Shortcut finished" : "Shortcut failed", tint: r.status == 0 ? .green : .red))
                }
            }
        }
    }

    /// A hung shortcut is stopped after `timeout` seconds, so the next run is not blocked behind it.
    private nonisolated static func exec(_ args: [String], timeout: TimeInterval = 0) -> (status: Int32, output: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return (-1, "") }
        if timeout > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
