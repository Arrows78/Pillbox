import Foundation

/// Runs a command-line tool and collects what it prints, for every place that needs another program's output.
enum ProcessRunner {
    /// Runs `executable` with `arguments` and returns its exit status and its output (stdout and stderr together).
    /// With a `timeout` the process is terminated once the time is up and the status is 124, like coreutils `timeout`.
    /// A program that cannot be launched gives status 127. The call returns at the timeout even when a child of the
    /// command still holds the output open; that child is not killed.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval? = nil, environment: [String: String]? = nil) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
        // Added to the inherited environment, so a variable such as GITLAB_HOST reaches the tool without replacing the rest.
        if let environment { p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new } }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { return (127, "") }
        // The output is read on another thread so that the wait below can give up on it.
        let collected = OutputBox(), finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            collected.data = pipe.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        if let timeout, finished.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            // Once the command is gone, its output is only collected if it ends within a second.
            let gotOutput = finished.wait(timeout: .now() + 1) == .success
            p.waitUntilExit()
            return (124, gotOutput ? String(decoding: collected.data, as: UTF8.self) : "")
        }
        if timeout == nil { finished.wait() }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: collected.data, as: UTF8.self))
    }
}

/// Output read on a background thread; the semaphore makes the write visible before it is read.
private final class OutputBox: @unchecked Sendable {
    var data = Data()
}
