import AppKit
import CryptoKit

// MARK: Automatic updates (GitHub releases, opt-in)

/// Why an update could not be downloaded or installed. The text is what the island shows.
enum UpdateError: Error, LocalizedError {
    case download, checksumMissing, checksumMismatch, save, unpack, notPillbox, install
    var errorDescription: String? {
        switch self {
        case .download: L("The download failed")
        case .checksumMissing: L("The checksum is missing, so the update was not installed")
        case .checksumMismatch: L("The checksum does not match")
        case .save: L("Could not save the download")
        case .unpack: L("Could not unpack the download")
        case .notPillbox: L("The archive is not a Pillbox release")
        case .install: L("The update could not be installed")
        }
    }
}

/// When the daily checks are due. Shared by the app update check and the Homebrew check.
enum DailyCheck {
    /// Due once a day, and only when the switch is on.
    nonisolated static func due(enabled: Bool, last: Date?, now: Date) -> Bool {
        enabled && (last.map { now.timeIntervalSince($0) >= 86_400 } ?? true)
    }
}

/// Checks GitHub once a day when the user turned it on, shows an island with an Update button, and installs the
/// release in place: the zip is downloaded, its SHA-256 checked against the published one, unpacked, swapped in and relaunched.
@MainActor
final class Updater {
    static let shared = Updater()
    nonisolated static let autoKey = "autoUpdate", lastKey = "lastUpdateCheck"
    private var timer: Timer?
    private var busy = false

    struct Release { let version: String; let page: URL?; let zip: URL?; let sha: URL? }

    nonisolated static func release(from json: [String: Any]) -> Release? {
        guard let tag = json["tag_name"] as? String else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        func asset(_ suffix: String) -> URL? {
            guard let s = assets.first(where: { ($0["name"] as? String)?.hasSuffix(suffix) == true })?["browser_download_url"] as? String,
                  let u = URL(string: s), u.scheme == "https", u.host == "github.com" else { return nil }
            return u
        }
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), page: UpdateCheck.releasePage(from: json), zip: asset(".zip"), sha: asset(".sha256"))
    }

    /// The hex digest in a `shasum` line ("abc…  Pillbox-1.0.zip").
    nonisolated static func digest(in text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map(String.init).flatMap { $0.count == 64 && $0.allSatisfy(\.isHexDigit) ? $0.lowercased() : nil }
    }

    nonisolated static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { MainActor.assumeIsolated { self.tick() } }
    }

    private func tick() {
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date
        guard DailyCheck.due(enabled: UserDefaults.standard.bool(forKey: Self.autoKey), last: last, now: Date()) else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastKey)
        fetch { [weak self] r in self?.offer(r) }
    }

    /// With the beta switch on, the newest release counts even when it is a pre-release: GitHub lists them newest first.
    nonisolated static let betaKey = "betaUpdates"

    func fetch(_ done: @escaping @MainActor (Release?) -> Void) {
        let beta = UserDefaults.standard.bool(forKey: Self.betaKey)
        let endpoint = beta ? UpdateCheck.api.replacingOccurrences(of: "/releases/latest", with: "/releases?per_page=1") : UpdateCheck.api
        guard let url = URL(string: endpoint) else { done(nil); return }
        var req = URLRequest(url: url); req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let body = (resp as? HTTPURLResponse)?.statusCode == 200 ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) } : nil
            let json = (body as? [String: Any]) ?? (body as? [[String: Any]])?.first
            let r = json.flatMap(Self.release(from:))
            DispatchQueue.main.async { MainActor.assumeIsolated { done(r) } }
        }.resume()
    }

    private func offer(_ r: Release?) {
        guard let r, UpdateCheck.isNewer(r.version, than: Diagnostics.version) else { return }
        NotchModel.shared.show(Activity(symbol: "arrow.down.app.fill", title: L("Pillbox %@ is available", r.version), subtitle: L("You are using version %@.", Diagnostics.version), tint: .blue,
                                        actionTitle: L("Update"), action: { [weak self] in self?.install(r) }, duration: 10))
    }

    /// Where the running app lives; nil when it cannot be replaced (not writable, not a bundle).
    static var installTarget: URL? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app", FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else { return nil }
        return app
    }

    func install(_ r: Release) {
        guard !busy else { return }
        guard let zip = r.zip, let target = Self.installTarget else { if let p = r.page { NSWorkspace.shared.open(p) }; return }
        busy = true
        NotchModel.shared.show(Activity(symbol: "arrow.down.circle", title: L("Downloading Pillbox %@…", r.version), tint: .blue, duration: 60))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-update-\(UUID().uuidString)", isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.download(zip: zip, sha: r.sha, version: r.version, into: dir)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.busy = false
                    switch result {
                    case .failure(let why):
                        try? FileManager.default.removeItem(at: dir)
                        NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: L("Could not update"), subtitle: why.localizedDescription, tint: .orange,
                                                        actionTitle: r.page == nil ? nil : L("Release page"), action: { if let p = r.page { NSWorkspace.shared.open(p) } }, duration: 8))
                    case .success(let app):
                        // Only claim the install once the swap has started; otherwise say so and keep the installed app.
                        if Self.swap(new: app, into: target) {
                            NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: L("Installing the update…"), tint: .green, duration: 5))
                        } else {
                            try? FileManager.default.removeItem(at: dir)
                            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: L("Could not update"), subtitle: UpdateError.install.localizedDescription, tint: .orange, duration: 8))
                        }
                    }
                }
            }
        }
    }

    nonisolated static func download(zip: URL, sha: URL?, version: String, into dir: URL) -> Result<URL, UpdateError> {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: zip), data.count > 1000 else { return .failure(.download) }
        // Fails closed: an update without its checksum is not installed.
        guard let sha, let text = try? String(contentsOf: sha, encoding: .utf8) else { return .failure(.checksumMissing) }
        guard let expected = digest(in: text), expected == sha256(data) else { return .failure(.checksumMismatch) }
        let file = dir.appendingPathComponent("Pillbox.zip")
        guard (try? data.write(to: file)) != nil else { return .failure(.save) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-x", "-k", file.path, dir.path]; p.standardError = Pipe(); p.standardOutput = Pipe()
        guard (try? p.run()) != nil else { return .failure(.unpack) }
        p.waitUntilExit()
        let app = dir.appendingPathComponent("Pillbox.app")
        guard p.terminationStatus == 0, let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let v = info["CFBundleShortVersionString"] as? String, !UpdateCheck.isNewer(version, than: v) else { return .failure(.notPillbox) }
        return .success(app)
    }

    /// Replaces the app once this process has exited, then relaunches it. Quarantine is dropped: the user asked for the install.
    /// Returns false when the helper could not be started, in which case nothing has been replaced.
    private static func swap(new: URL, into target: URL) -> Bool {
        // Paths go in as arguments, not inside the script, so spaces and quotes in them cannot break it. The copy is
        // made beside the old app and moved over it only once complete: a failed copy leaves the installed app in place.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        if rm -rf "$2.new" && ditto "$3" "$2.new" && rm -rf "$2" && mv "$2.new" "$2"; then
            xattr -dr com.apple.quarantine "$2" 2>/dev/null
            rm -rf "$(dirname "$3")"
        fi
        open "$2"
        """
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", script, "pillbox-update", String(ProcessInfo.processInfo.processIdentifier), target.path, new.path]
        p.standardOutput = nil; p.standardError = nil
        guard (try? p.run()) != nil else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        return true
    }
}

// MARK: Homebrew updates (opt-in)

/// Once a day, `brew outdated` lists the packages with a newer version; the island offers to upgrade them in the Terminal tab.
@MainActor
final class BrewUpdates {
    static let shared = BrewUpdates()
    nonisolated static let key = "brewUpdates", lastKey = "lastBrewCheck"
    private var timer: Timer?
    nonisolated static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    nonisolated static var brew: String? { candidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

    /// Package names, one per line, from `brew outdated --quiet`.
    nonisolated static func parse(_ output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("==>") && !$0.hasPrefix("Warning") }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { self.tick() } }
    }

    private func tick() {
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date
        guard DailyCheck.due(enabled: UserDefaults.standard.bool(forKey: Self.key), last: last, now: Date()) else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastKey)
        check(quiet: true)
    }

    /// From the palette too: `quiet` only speaks when something is outdated.
    func check(quiet: Bool) {
        guard let brew = Self.brew else { if !quiet { NotchModel.shared.show(Activity(symbol: "shippingbox", title: L("Homebrew is not installed"), tint: .orange)) }; return }
        DispatchQueue.global(qos: .utility).async {
            let r = ActionRunner.runShell("\"\(brew)\" outdated --quiet", timeout: 120)
            let names = r.status == 0 ? Self.parse(r.output) : []
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if names.isEmpty {
                        if !quiet { NotchModel.shared.show(Activity(symbol: "shippingbox", title: r.status == 0 ? L("Homebrew is up to date") : L("Could not run brew outdated"), tint: r.status == 0 ? .green : .orange)) }
                        return
                    }
                    NotchModel.shared.show(Activity(symbol: "shippingbox.fill", title: L("%d Homebrew update(s)", names.count), subtitle: names.prefix(4).joined(separator: ", "), tint: .yellow,
                                                    actionTitle: L("Upgrade"), action: { Self.upgradeInTerminal(brew) }, duration: 8))
                }
            }
        }
    }

    /// Opens the Terminal tab and types the command there, so the output stays readable and any password prompt is yours.
    private static func upgradeInTerminal(_ brew: String) {
        NotchModel.shared.pinnedOpen = true
        NotchModel.shared.expand(.terminal)
        typeWhenRunning("\"\(brew)\" upgrade\n")
    }

    /// Types into the shell once its process is running, rather than after a fixed delay. After about 2 s it types anyway.
    private static func typeWhenRunning(_ text: String, attempts: Int = 40) {
        let view = TerminalSession.shared.view
        if view.process?.running == true || attempts == 0 { view.send(txt: text); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { MainActor.assumeIsolated { typeWhenRunning(text, attempts: attempts - 1) } }
    }
}
