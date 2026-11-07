import AppKit

struct LyricLine: Identifiable { let id = UUID(); let time: Double; let text: String }

enum Player: String {
    case spotify = "Spotify", music = "Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published var player: Player?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var lyrics: [LyricLine] = []
    @Published var shuffling = false
    @Published var repeating = false

    private let queue = DispatchQueue(label: "pillbox.applescript")
    private var timer: Timer?
    private var trackKey = ""
    private var lastPoll = Date()

    var hasTrack: Bool { player != nil && !title.isEmpty }

    var currentLyric: String? {
        guard !lyrics.isEmpty else { return nil }
        return lyrics.last(where: { $0.time <= position + 0.2 })?.text
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func running(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    private func poll() {
        // Interpolate between polls so the progress bar stays smooth.
        let candidates = [Player.spotify, .music].filter(running)
        guard !candidates.isEmpty else { clear(); return }
        let wanted = candidates.contains(player ?? .spotify) ? (player ?? candidates[0]) : candidates[0]
        fetch(wanted, fallback: candidates.first(where: { $0 != wanted }))
    }

    private func clear() {
        if player != nil { player = nil; title = ""; artist = ""; isPlaying = false; artwork = nil; lyrics = []; trackKey = "" }
    }

    private func fetch(_ p: Player, fallback: Player?) {
        let script: String
        if p == .spotify {
            script = """
            tell application "Spotify"
              if player state is stopped then return {"stopped"}
              return {player state as text, name of current track, artist of current track, album of current track, (duration of current track) / 1000, player position, artwork url of current track, shuffling as text, repeating as text}
            end tell
            """
        } else {
            script = """
            tell application "Music"
              if player state is stopped then return {"stopped"}
              return {player state as text, name of current track, artist of current track, album of current track, duration of current track, player position, "", shuffle enabled as text, ((song repeat as text) is not "off") as text}
            end tell
            """
        }
        queue.async { [weak self] in
            let d = Self.run(script)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(d, player: p, fallback: fallback) }
            }
        }
    }

    private func apply(_ d: NSAppleEventDescriptor?, player p: Player, fallback: Player?) {
        guard let d, d.numberOfItems >= 6, d.atIndex(1)?.stringValue != "stopped" else {
            if let fallback { fetch(fallback, fallback: nil) } else { clear() }
            return
        }
        func str(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        func num(_ i: Int) -> Double { Double(str(i).replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let playing = str(1) == "playing"
        shuffling = str(8) == "true"; repeating = str(9) == "true"
        if !playing, let fallback, !isPlaying, player != fallback {
            // Prefer whichever app is actually playing.
            fetch(fallback, fallback: nil)
        }
        player = p
        isPlaying = playing
        duration = num(5)
        position = num(6)
        let key = "\(p.rawValue)|\(str(2))|\(str(3))"
        if key != trackKey {
            trackKey = key
            title = str(2); artist = str(3); album = str(4)
            artwork = nil; lyrics = []
            loadArtwork(p, url: str(7))
            loadLyrics()
        }
    }

    private func loadArtwork(_ p: Player, url: String) {
        if p == .spotify, let u = URL(string: url) {
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self.artwork = img } }
            }.resume()
        } else if p == .music {
            queue.async { [weak self] in
                let d = Self.run("tell application \"Music\" to return data of artwork 1 of current track")
                guard let data = d?.data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.artwork = img } }
            }
        }
    }

    /// Time-synced lyrics from LRCLIB (free, no key).
    private func loadLyrics() {
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title),
                        .init(name: "album_name", value: album), .init(name: "duration", value: String(Int(duration)))]
        guard let url = c.url else { return }
        let key = trackKey
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrc = obj["syncedLyrics"] as? String else { return }
            let lines = Self.parseLRC(lrc)
            DispatchQueue.main.async { MainActor.assumeIsolated { if self.trackKey == key { self.lyrics = lines } } }
        }.resume()
    }

    nonisolated static func parseLRC(_ s: String) -> [LyricLine] {
        s.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let sec = Double(stamp[1]) else { return nil }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : LyricLine(time: m * 60 + sec, text: text)
        }
    }

    // MARK: Controls

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func toggleShuffle() {
        guard let p = player else { return }
        shuffling.toggle()
        command(p == .spotify ? "set shuffling to \(shuffling)" : "set shuffle enabled to \(shuffling)")
    }

    func toggleRepeat() {
        guard let p = player else { return }
        repeating.toggle()
        command(p == .spotify ? "set repeating to \(repeating)" : "set song repeat to \(repeating ? "all" : "off")")
    }

    /// Apple Music only: Spotify's scripting interface has no favourite.
    func favorite() {
        guard player == .music else { return }
        command("set favorited of current track to true")
        NotchModel.shared.show(Activity(symbol: "heart.fill", title: "Added to favorites", tint: .pink, duration: 1.5))
    }

    func seek(to t: Double) { position = t; command("set player position to \(t)") }

    private func command(_ c: String) {
        guard let p = player else { return }
        queue.async { _ = Self.run("tell application \"\(p.rawValue)\" to \(c)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { self.poll() } }
    }

    func openPlayer() {
        if let p = player, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    nonisolated static func run(_ source: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&err)
    }
}
