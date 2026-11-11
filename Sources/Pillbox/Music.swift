import AppKit

enum MusicApp: String {
    case spotify = "Spotify", music = "Music"
    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

@MainActor
final class MusicService: ObservableObject {
    static let shared = MusicService()

    @Published var player: MusicApp?
    /// The player is open but Pillbox may not control it: Automation is off for it.
    @Published private(set) var automationDenied: MusicApp?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var duration: Double = 0
    /// Set on every poll or seek; the playhead is estimated from it between polls.
    @Published var position: Double = 0 { didSet { polledAt = Date() } }
    private var polledAt = Date()
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var lyrics: [LyricLine] = []
    @Published var shuffling = false
    @Published var repeating = false
    /// The player's own volume, 0 to 100, set from the Music tab.
    @Published private(set) var volume = 50
    /// Apple Music's favourite state of the current track. Spotify's scripting interface has none.
    @Published private(set) var favorited = false

    private let queue = DispatchQueue(label: "pillbox.applescript")
    /// Moves the playhead on while a track plays. It runs only then, and asks the player again every
    /// `resyncTicks` seconds to catch a seek made in the player itself.
    private var ticker: Timer?
    private var ticks = 0
    static let resyncTicks = 15
    private var observers: [NSObjectProtocol] = []
    private var trackKey = ""

    /// What a browser tab is playing, when no Spotify or Music player is in use and the setting allows it.
    @Published private(set) var browserNow: BrowserMusic.Now?
    private var browserTimer: Timer?

    var hasTrack: Bool { (player != nil || browserNow != nil) && !title.isEmpty }

    /// The line being sung, with its word stamps.
    var currentLine: LyricLine? { lyrics.last(where: { $0.time <= position + 0.2 }) }

    /// Where playback is at `date`: the last reading, moved on by the time since while playing, so word highlights stay smooth.
    func playhead(at date: Date) -> Double { position + (isPlaying ? max(0, date.timeIntervalSince(polledAt)) : 0) }

    /// The notifications Spotify and Music post on every change of track, state or position.
    nonisolated static let playerNotifications = ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"]

    /// Reads the players when they say something changed, instead of asking them every second.
    func start() {
        let distributed = DistributedNotificationCenter.default()
        for name in Self.playerNotifications {
            observers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            })
        }
        // A player that opens or quits posts nothing: its launch and its end are read from the workspace.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                guard Self.isPlayer(id) else { return }
                MainActor.assumeIsolated { self?.poll() }
            })
        }
        poll()
        // Browsers post no notification, so their tab is read on a short timer; it does nothing while a player is in use.
        browserTimer = PowerGate.timer(every: 3) { [weak self] in self?.pollBrowser() }
    }

    nonisolated static func isPlayer(_ bundleID: String?) -> Bool {
        [MusicApp.spotify.bundleID, MusicApp.music.bundleID].contains(bundleID ?? "")
    }

    /// Starts or stops the playhead ticker so it runs exactly while a track plays.
    private func updateTicker() {
        if isPlaying, ticker == nil {
            ticks = 0
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } else if !isPlaying, let t = ticker {
            t.invalidate(); ticker = nil
        }
    }

    private func tick() {
        ticks += 1
        if ticks % Self.resyncTicks == 0 { poll(); return }
        position = Self.advanced(position, by: 1, duration: duration)
    }

    /// The playhead one step later, held at the end of the track.
    nonisolated static func advanced(_ position: Double, by step: Double, duration: Double) -> Double {
        duration > 0 ? min(position + step, duration) : position + step
    }

    private func running(_ p: MusicApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    private func poll() {
        // Interpolate between polls so the progress bar stays smooth.
        let candidates = [MusicApp.spotify, .music].filter(running)
        guard !candidates.isEmpty else { clear(); return }
        // Keep the current player while it is running, otherwise take the first running one.
        var wanted = candidates[0]
        if let current = player, candidates.contains(current) { wanted = current }
        fetch(wanted, fallback: candidates.first(where: { $0 != wanted }))
    }

    private func clear() {
        if player != nil { player = nil; title = ""; artist = ""; isPlaying = false; favorited = false; artwork = nil; lyrics = []; trackKey = "" }
        updateTicker()
    }

    /// Music in a browser tab, read every few seconds while no Spotify or Music player is in use. Off unless allowed.
    private func pollBrowser() {
        guard Preferences.browserMusic.value, player == nil else {
            if player != nil, browserNow != nil { browserNow = nil }
            return
        }
        queue.async { [weak self] in
            let now = BrowserMusic.read()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyBrowser(now) } }
        }
    }

    private func applyBrowser(_ now: BrowserMusic.Now?) {
        guard player == nil else { return }
        guard let now else {
            if browserNow != nil { browserNow = nil; title = ""; artist = ""; isPlaying = false; duration = 0; position = 0 }
            return
        }
        browserNow = now
        title = now.title; artist = now.browser
        isPlaying = now.playing; duration = now.duration; position = now.position
        updateTicker()
    }

    /// `probing`: this read only checks whether the other player is playing; it changes nothing unless it is.
    private func fetch(_ p: MusicApp, fallback: MusicApp?, probing: Bool = false) {
        let script: String
        if p == .spotify {
            script = """
            tell application "Spotify"
              if player state is stopped then return {"stopped"}
              return {player state as text, name of current track, artist of current track, album of current track, (duration of current track) / 1000, player position, artwork url of current track, shuffling as text, repeating as text, "false", sound volume as text}
            end tell
            """
        } else {
            script = """
            tell application "Music"
              if player state is stopped then return {"stopped"}
              -- "favorited" is recent; an older Music without it still answers, with no favourite.
              set fav to "false"
              try
                set fav to (favorited of current track) as text
              end try
              return {player state as text, name of current track, artist of current track, album of current track, duration of current track, player position, "", shuffle enabled as text, ((song repeat as text) is not "off") as text, fav, sound volume as text}
            end tell
            """
        }
        queue.async { [weak self] in
            let d = Self.run(script)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(d, player: p, fallback: fallback, probing: probing) }
            }
        }
    }

    private func apply(_ d: NSAppleEventDescriptor?, player p: MusicApp, fallback: MusicApp?, probing: Bool = false) {
        // No answer at all from a running player means Automation refused it. A "stopped" answer is a normal state.
        guard let d, d.numberOfItems >= 6, d.atIndex(1)?.stringValue != "stopped" else {
            if probing { return }
            if let fallback { fetch(fallback, fallback: nil) } else {
                automationDenied = d == nil && running(p) ? p : nil
                clear()
            }
            return
        }
        automationDenied = nil
        func str(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        func num(_ i: Int) -> Double { Double(str(i).replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let playing = str(1) == "playing"
        // A probe that finds the other player silent leaves the state alone, so the shown player does not flip every poll.
        if probing && !playing { return }
        shuffling = str(8) == "true"; repeating = str(9) == "true"; favorited = str(10) == "true"; volume = Int(str(11)) ?? volume
        if !playing, let fallback, !isPlaying, player != fallback {
            // Prefer whichever app is actually playing: its answer decides, this one's state is still written below.
            fetch(fallback, fallback: nil, probing: true)
        }
        browserNow = nil
        player = p
        isPlaying = playing
        duration = num(5)
        position = num(6)
        ticks = 0
        updateTicker()
        let key = "\(p.rawValue)|\(str(2))|\(str(3))"
        if key != trackKey {
            trackKey = key
            title = str(2); artist = str(3); album = str(4)
            artwork = nil; lyrics = []
            loadArtwork(p, url: str(7))
            loadLyrics()
        }
    }

    private func loadArtwork(_ p: MusicApp, url: String) {
        let key = trackKey
        if p == .spotify, let u = URL(string: url) {
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { if self.trackKey == key { self.artwork = img } } }
            }.resume()
        } else if p == .music {
            queue.async { [weak self] in
                let d = Self.run("tell application \"Music\" to return data of artwork 1 of current track")
                guard let data = d?.data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.trackKey == key { self?.artwork = img } } }
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
        var lines: [LyricLine] = s.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let sec = Double(stamp[1]) else { return nil }
            let (text, words) = wordStamps(String(line[line.index(after: close)...]))
            return text.isEmpty ? nil : LyricLine(time: m * 60 + sec, text: text, words: words)
        }
        // A line without word stamps spreads its words across the time up to the next line.
        for i in lines.indices where lines[i].words.isEmpty {
            let start = lines[i].time, end = i + 1 < lines.count ? lines[i + 1].time : start + 4
            let parts = lines[i].text.split(separator: " ").map(String.init)
            let span = max(end - start, 0.1)
            lines[i].words = parts.enumerated().map { LyricWord(time: start + span * Double($0.offset) / Double(parts.count), text: $0.element) }
        }
        return lines
    }

    /// The text of a line and its word stamps when it has any, as in "<00:12.34>Hello <00:12.90>world".
    nonisolated static func wordStamps(_ body: String) -> (String, [LyricWord]) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("<"), let pattern = try? NSRegularExpression(pattern: #"<(\d+):(\d+(?:[.,]\d+)?)>([^<]*)"#) else { return (trimmed, []) }
        let ns = trimmed as NSString
        var words: [LyricWord] = []
        let matches = pattern.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let mi = Double(ns.substring(with: m.range(at: 1))),
                  let se = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ",", with: ".")) else { continue }
            let word = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { words.append(LyricWord(time: mi * 60 + se, text: word)) }
        }
        guard !words.isEmpty else { return (trimmed, []) }
        // Text before the first stamp is sung at the first stamp's time, so it is kept rather than dropped.
        let leadEnd = matches.first?.range.location ?? ns.length
        let lead = ns.substring(to: leadEnd).trimmingCharacters(in: .whitespaces)
        if !lead.isEmpty { words.insert(contentsOf: lead.split(separator: " ").map { LyricWord(time: words[0].time, text: String($0)) }, at: 0) }
        return (words.map(\.text).joined(separator: " "), words)
    }

    // MARK: Controls

    func playPause() {
        if player == nil, let now = browserNow {
            queue.async { BrowserMusic.togglePlayback(bundleID: now.bundleID) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self.pollBrowser() } }
            return
        }
        command("playpause")
    }
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

    /// Apple Music only: Spotify's scripting interface has no favourite. Adds the track, or removes it when it is one.
    func favorite() {
        guard player == .music else { return }
        favorited.toggle()
        command("set favorited of current track to \(favorited)")
        NotchModel.shared.show(Activity(symbol: favorited ? "heart.fill" : "heart.slash", title: localized(favorited ? "Added to favorites" : "Removed from favorites"),
                                        tint: .pink, duration: 1.5))
    }

    func seek(to t: Double) { position = t; command("set player position to \(t)") }

    /// Sets the player's sound volume, 0 to 100.
    nonisolated static func clampVolume(_ v: Int) -> Int { min(max(v, 0), 100) }

    func setVolume(_ v: Int) {
        let clamped = Self.clampVolume(v)
        volume = clamped
        command("set sound volume to \(clamped)")
    }

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
