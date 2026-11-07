import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

/// Non-interactive checks behind `--selftest` (no window, no permission, no network).
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print("\(ok ? "PASS" : "FAIL")  \(name)\(ok ? "" : "  \(detail())")")
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        lyrics(); math(); formatting(); clipboard(); stocks(); snapping(); weather(); timer(); usage(); geometry(); stores(); shelf(); palette(); snippets(); watchers(); converter(); reminders(); extras(); batch3()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    private static func lyrics() {
        let l = MusicService.parseLRC("[00:12.50] Hello\n[01:02.00]World\n[00:30.00]\nnot a line")
        check("LRC parses timestamps and skips empty lines", l.count == 2 && l[0].time == 12.5 && l[1].time == 62 && l[1].text == "World", "\(l.map(\.time))")
    }

    private static func math() {
        check("palette math precedence", PaletteModel.evaluate("2+3*4") == "14", PaletteModel.evaluate("2+3*4") ?? "nil")
        check("palette math division", PaletteModel.evaluate("10/4") == "2.5", PaletteModel.evaluate("10/4") ?? "nil")
        check("palette math parentheses", PaletteModel.evaluate("(1+2)*3") == "9", PaletteModel.evaluate("(1+2)*3") ?? "nil")
        check("palette math rejects text", PaletteModel.evaluate("abc") == nil && PaletteModel.evaluate("42") == nil)
        check("palette math rejects code", PaletteModel.evaluate("FUNCTION(1,'x')+1") == nil)
    }

    private static func formatting() {
        check("timer format minutes", TimerService.format(65) == "01:05", TimerService.format(65))
        check("timer format hours", TimerService.format(3725) == "1:02:05", TimerService.format(3725))
        check("token shortening", AIUsageService.short(999) == "999" && AIUsageService.short(12_400) == "12k" && AIUsageService.short(2_500_000) == "2.5M")
    }

    private static func clipboard() {
        if case .url = ClipboardService.kind(of: "https://example.com/a") {} else { check("clipboard detects URL", false) }
        if case .color(_, let h) = ClipboardService.kind(of: "#ff8800") { check("clipboard detects hex colour", h == "#ff8800") } else { check("clipboard detects hex colour", false) }
        if case .email = ClipboardService.kind(of: "a@b.co") {} else { check("clipboard detects email", false) }
        if case .plain = ClipboardService.kind(of: "hello world") { check("clipboard keeps plain text", true) } else { check("clipboard keeps plain text", false) }
        check("hex round trip", NSColor(hex: "#336699")?.hexString == "#336699", NSColor(hex: "#336699")?.hexString ?? "nil")
        check("short hex expands", NSColor(hex: "f80")?.hexString == "#FF8800", NSColor(hex: "f80")?.hexString ?? "nil")
    }

    private static func stocks() {
        let now = Date().timeIntervalSince1970
        let json = """
        {"chart":{"result":[{"meta":{"regularMarketPrice":110.0,"chartPreviousClose":100.0,
         "currentTradingPeriod":{"pre":{"start":0,"end":1},"regular":{"start":\(now - 100),"end":\(now + 100)},"post":{"start":\(now + 100),"end":\(now + 200)}}},
         "indicators":{"quote":[{"close":[100.0,null,105.0,110.0]}]}}]}}
        """
        let q = StocksService.parse(Data(json.utf8), symbol: "TEST")
        check("quote parses price, change and state", q?.price == 110 && abs((q?.change ?? 0) - 0.10) < 1e-9 && q?.state == "Open", "\(String(describing: q))")
        check("quote skips null closes", q?.series == [100, 105, 110], "\(q?.series ?? [])")
        check("quote rejects garbage", StocksService.parse(Data("{}".utf8), symbol: "X") == nil)
    }

    private static func snapping() {
        let r = CGRect(x: 0, y: 0, width: 1200, height: 800)
        check("snap left half", SnapZone.left.frame(in: r) == CGRect(x: 0, y: 0, width: 600, height: 800))
        check("snap right half", SnapZone.right.frame(in: r) == CGRect(x: 600, y: 0, width: 600, height: 800))
        check("snap right third", SnapZone.rightThird.frame(in: r) == CGRect(x: 800, y: 0, width: 400, height: 800))
        check("snap full", SnapZone.full.frame(in: r) == r)
    }

    private static func weather() {
        check("weather code mapping", WeatherService.describe(0, day: true).0 == "sun.max.fill" && WeatherService.describe(95, day: true).1 == "Thunderstorm" && WeatherService.describe(61, day: false).1 == "Rain")
    }

    private static func timer() {
        let t = TimerService()
        t.mode = .countdown; t.countdownMinutes = 1
        check("countdown starts at its length", Int(t.seconds) == 60, "\(t.seconds)")
        t.start()
        check("countdown runs", t.running)
        t.pause()
        let frozen = t.seconds
        check("pause keeps the remaining time", !t.running && frozen > 58 && frozen <= 60, "\(frozen)")
        t.reset()
        check("reset restores the length", Int(t.seconds) == 60 && !t.isActive)
        t.mode = .stopwatch
        check("stopwatch starts at zero", t.seconds == 0)
    }

    private static func usage() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pillbox-selftest-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let claude = root.appendingPathComponent("claude/proj"), codex = root.appendingPathComponent("codex/2026/11/07")
        try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
        try? fm.createDirectory(at: codex, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recent = iso.string(from: now.addingTimeInterval(-600)), old = iso.string(from: now.addingTimeInterval(-3 * 86400))
        // Claude Code logs each content block of one response: the id must be counted once.
        let line = { (id: String, ts: String, i: Int, o: Int) in
            "{\"timestamp\":\"\(ts)\",\"requestId\":\"r\(id)\",\"message\":{\"id\":\"m\(id)\",\"usage\":{\"input_tokens\":\(i),\"output_tokens\":\(o),\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1000}}}"
        }
        let body = [line("1", recent, 100, 50), line("1", recent, 100, 50), line("2", old, 10, 5), "garbage"].joined(separator: "\n")
        try? body.write(to: claude.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let c = AIUsageService.scanClaude(now: now, root: root.appendingPathComponent("claude"))
        check("claude: duplicate message counted once", c.fiveHour == 150, "\(c.fiveHour)")
        check("claude: older entries only in the week", c.week == 165 && c.today >= 150, "week \(c.week) today \(c.today)")
        check("claude: cache reads kept apart", c.cacheRead == 2000, "\(c.cacheRead)")
        check("claude: seven day buckets", c.days.count == 7 && c.days.last?.tokens == c.today)

        let reset = now.timeIntervalSince1970 + 3600
        let ev = { (ts: String, total: Int, input: Int, cached: Int, out: Int, resets: Double) in
            "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(total)},\"last_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),\"output_tokens\":\(out)}},\"rate_limits\":{\"primary\":{\"used_percent\":42.0,\"window_minutes\":300,\"resets_at\":\(resets)}}}}"
        }
        let cbody = [ev(recent, 1000, 1000, 800, 100, reset), ev(recent, 1000, 1000, 800, 100, reset), ev(recent, 2500, 1500, 500, 50, reset)].joined(separator: "\n")
        try? cbody.write(to: codex.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
        let x = AIUsageService.scanCodex(now: now, root: root.appendingPathComponent("codex"))
        check("codex: repeated cumulative total counted once", x.fiveHour == (200 + 100) + (1000 + 50), "\(x.fiveHour)")
        check("codex: reports the limit window", x.limitPercent == 42 && x.limitWindowMinutes == 300, "\(String(describing: x.limitPercent))")
        let past = AIUsageService.scanCodex(now: now.addingTimeInterval(7200), root: root.appendingPathComponent("codex"))
        check("codex: an expired limit window is dropped", past.limitPercent == nil)
    }

    private static func geometry() {
        let m = NotchModel()
        m.geometry = NotchGeometry(width: 185, height: 32, screen: nil)
        check("collapsed pill is the notch size", m.size(hasWings: false) == CGSize(width: 185, height: 32))
        check("wings widen the pill", m.size(hasWings: true).width == 185 + NotchModel.wing * 2)
        m.expanded = true
        check("expanded size", m.size(hasWings: false) == NotchModel.expandedSize)
        m.tab = .terminal
        check("terminal tab is larger", m.size(hasWings: false).height > NotchModel.expandedSize.height)
        var decided = ""
        m.requestApproval(tool: "Bash", detail: "ls", timeout: 60) { decided = $0 }
        check("approval takes over the island", m.size(hasWings: false).width == 520 && m.approval != nil)
        m.resolveApproval("allow")
        check("approval answers once and clears", decided == "allow" && m.approval == nil)
    }

    private static func stores() {
        let notes = NotesStore()
        notes.draft = "  buy milk  "; notes.add()
        notes.draft = "   "; notes.add()
        check("notes: add trims and ignores blanks", notes.notes.count == 1 && notes.notes[0].text == "buy milk")
        notes.toggle(notes.notes[0])
        check("notes: toggle marks done", notes.notes[0].done)
        let persisted = Store.load("notes.json", as: [Note].self)
        check("notes: saved to disk", persisted?.count == 1 && persisted?[0].done == true)
        notes.clearDone()
        check("notes: clear done", notes.notes.isEmpty)

        let launcher = LauncherStore()
        launcher.paths = ["/A", "/B", "/C"]
        launcher.move("/C", onto: "/A")
        check("launcher: C takes A's slot", launcher.paths == ["/C", "/A", "/B"], "\(launcher.paths)")
        launcher.move("/A", onto: "/B")
        check("launcher: moving forward takes the target's slot", launcher.paths == ["/C", "/B", "/A"], "\(launcher.paths)")
        launcher.move("/A", onto: "/A")
        check("launcher: dropping on itself changes nothing", launcher.paths == ["/C", "/B", "/A"])

        let clip = ClipboardService()
        clip.items = (0..<(ClipboardService.cap + 10)).map { ClipItem(text: "item \($0)", date: Date(timeIntervalSinceNow: Double($0))) }
        clip.items[0].pinned = true   // the oldest item, pinned: it must survive the cap
        clip.trim()
        check("clipboard: cap keeps pinned items", clip.items.count == ClipboardService.cap + 1 && clip.items.contains { $0.pinned }, "\(clip.items.count)")
        check("clipboard: pinned sort first", clip.filtered.first?.pinned == true)
        clip.query = "item 69"
        check("clipboard: search", clip.filtered.map(\.text) == ["item 69"], "\(clip.filtered.map(\.text))")
        var withOCR = ClipItem(imageFile: "x.png"); withOCR.ocr = "invoice total 42"
        clip.items.append(withOCR); clip.query = "invoice"
        check("clipboard: search finds text inside images", clip.filtered.count == 1)
    }

    private static func shelf() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pillbox-shelf-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("hello.txt")
        try? "hello".write(to: file, atomically: true, encoding: .utf8)
        let shelf = ShelfService()
        shelf.add([file, file])
        check("shelf: no duplicates", shelf.items.count == 1)
        shelf.zipOrUnzip(shelf.items)
        let zip = file.appendingPathExtension("zip")
        for _ in 0..<50 where !fm.fileExists(atPath: zip.path) || shelf.items.count < 2 { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        check("shelf: zip created and added", fm.fileExists(atPath: zip.path) && shelf.items.count == 2, "\(shelf.items.count)")
        let names = (try? Process.output("/usr/bin/zipinfo", ["-1", zip.path])) ?? ""
        check("shelf: zip of a file holds just that file", names.split(separator: "\n").filter { !$0.hasPrefix("__MACOSX") }.map(String.init) == ["hello.txt"], names)
        try? fm.removeItem(at: file)
        if let z = shelf.items.first(where: { $0.path == zip.path }) { shelf.zipOrUnzip([z]) }
        let out = zip.deletingPathExtension()   // "hello.txt" is free again: the archive expands into a folder of that name
        for _ in 0..<50 where !fm.fileExists(atPath: out.appendingPathComponent("hello.txt").path) { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        check("shelf: unzip restores the file in a new folder", (try? String(contentsOf: out.appendingPathComponent("hello.txt"), encoding: .utf8)) == "hello")
        try? "other".write(to: file, atomically: true, encoding: .utf8)   // now "hello.txt" exists as a file
        check("shelf: unique names never overwrite", ShelfService.uniqueURL(file).lastPathComponent == "hello 2.txt", ShelfService.uniqueURL(file).lastPathComponent)
        shelf.remove(Set(shelf.items.map(\.id)))
        check("shelf: remove", shelf.items.isEmpty)
    }

    private static func palette() {
        let m = PaletteModel()
        check("palette lists every tab", Tab.allCases.allSatisfy { t in m.commands.contains { $0.title.contains(L("Go to %@", t.title)) } })
        m.query = String(L("Snap window: %@", "").prefix(4))
        check("palette filters by query", !m.commands.isEmpty && m.commands.allSatisfy { $0.title.localizedCaseInsensitiveContains(m.query) }, m.query)
        m.query = "2+2*5"
        check("palette answers maths first", m.commands.first?.title.hasPrefix("= 12") == true, m.commands.first?.title ?? "none")
        m.query = "zzzz-no-such-command"
        check("palette offers only a web search for nonsense", m.commands.count == 1 && m.commands[0].title.contains("zzzz-no-such-command"), "\(m.commands.map(\.title))")
    }

    /// Runs an async operation to completion while keeping the main run loop alive.
    private static func wait<T>(_ op: @escaping () async throws -> T) -> Result<T, Error> {
        var result: Result<T, Error>?
        Task { @MainActor in do { result = .success(try await op()) } catch { result = .failure(error) } }
        let deadline = Date().addingTimeInterval(30)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return result ?? .failure(ConvertError.failed("timeout"))
    }

    private static func snippets() {
        let st = SnippetsStore.shared   // the palette reads the shared store
        st.snippets = []
        st.draftName = "Sign-off"; st.draftText = "Best regards,\nThomas"; st.add()
        st.draftName = "  "; st.draftText = "x"; st.add()
        st.draftName = "Empty"; st.draftText = "   "; st.add()
        check("snippets: add keeps valid, rejects blank name or text", st.snippets.count == 1 && st.snippets[0].text.contains("\n"), "\(st.snippets.count)")
        check("snippets: saved to disk", Store.load("snippets.json", as: [Snippet].self)?.count == 1)
        let m = PaletteModel(); m.query = "sign"
        check("snippets: found from the palette", m.commands.contains { $0.title == L("Snippet: %@", "Sign-off") })
        st.remove(st.snippets[0])
        check("snippets: remove", st.snippets.isEmpty)
    }

    private static func watchers() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pillbox-watch-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try? "old".write(to: dir.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        var seen: [String] = []
        let w = FolderWatcher(dir: dir) { seen.append($0.lastPathComponent) }
        w.start()
        for n in ["report.pdf", ".hidden", "movie.mp4.crdownload", "photo.png"] { try? "x".write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8) }
        w.changed(); w.changed()
        check("folder watcher: reports new files once, skips hidden and temporary", seen.sorted() == ["photo.png", "report.pdf"], "\(seen)")
        w.stop()

        let shot = dir.appendingPathComponent("photo.png")
        check("screenshot: untagged image is ignored", !ScreenshotWatcher.isScreenshot(shot))
        let tag = Array("1".utf8)
        setxattr(shot.path, "com.apple.metadata:kMDItemIsScreenCapture", tag, tag.count, 0, 0)
        check("screenshot: tagged image is recognised", ScreenshotWatcher.isScreenshot(shot))
        check("drive: the boot volume is not ejectable", !DriveWatcher.isEjectable(URL(fileURLWithPath: "/")))
    }

    private static func converter() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pillbox-conv-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // A 64x64 gradient PNG.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<64 { for y in 0..<64 { rep.setColor(NSColor(srgbRed: CGFloat(x) / 64, green: CGFloat(y) / 64, blue: 0.5, alpha: 1), atX: x, y: y) } }
        let png = dir.appendingPathComponent("pic.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: png)

        func type(of url: URL) -> String? { CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceGetType($0) as String? } }
        for (target, expected) in [(ConvertTarget.jpeg, "public.jpeg"), (.tiff, "public.tiff"), (.heic, "public.heic")] {
            switch wait({ try await Converter.convert(png, to: target) }) {
            case .success(let out): check("convert: PNG to \(target.rawValue)", type(of: out) == expected && out.pathExtension == target.ext, "\(type(of: out) ?? "nil")")
            case .failure(let e): check("convert: PNG to \(target.rawValue)", false, "\(e)")
            }
        }
        switch wait({ try await Converter.convert(png, to: .pdf) }) {
        case .success(let out): check("convert: PNG to PDF has one page", PDFDocument(url: out)?.pageCount == 1)
        case .failure(let e): check("convert: PNG to PDF has one page", false, "\(e)")
        }
        switch wait({ try await Converter.convert(png, to: .jpeg) }) {
        case .success(let out): check("convert: output never overwrites", out.lastPathComponent == "pic 2.jpg", out.lastPathComponent)
        case .failure(let e): check("convert: output never overwrites", false, "\(e)")
        }
        switch wait({ try await Converter.convert(png, to: .cutout) }) {
        case .success(let out): check("convert: cut-out returns a PNG, or a clean error without a subject", type(of: out) == "public.png")
        case .failure: check("convert: cut-out returns a PNG, or a clean error without a subject", true)
        }
        check("convert: targets by file type", ConvertTarget.targets(for: png).contains(.heic) && ConvertTarget.targets(for: URL(fileURLWithPath: "a.mov")).contains(.mp4)
              && ConvertTarget.targets(for: URL(fileURLWithPath: "a.wav")).contains(.aiff) && ConvertTarget.targets(for: URL(fileURLWithPath: "a.txt")).isEmpty)

        // One second of 440 Hz, 44.1 kHz mono, as WAV.
        let wav = dir.appendingPathComponent("tone.wav")
        if let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 1, interleaved: true),
           let file = try? AVAudioFile(forWriting: wav, settings: fmt.settings, commonFormat: .pcmFormatInt16, interleaved: true),
           let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44100) {
            buf.frameLength = 44100
            for i in 0..<44100 { buf.int16ChannelData![0][i] = Int16(10000 * sin(2 * .pi * 440 * Double(i) / 44100)) }
            try? file.write(from: buf)
        }
        switch wait({ try await Converter.convert(wav, to: .aiff) }) {
        case .success(let out): check("convert: WAV to AIFF keeps every frame", (try? AVAudioFile(forReading: out))?.length == 44100)
        case .failure(let e): check("convert: WAV to AIFF keeps every frame", false, "\(e)")
        }
        switch wait({ try await Converter.convert(wav, to: .m4a) }) {
        case .success(let out):
            let secs = (try? AVAudioFile(forReading: out)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            check("convert: WAV to M4A keeps the duration", abs(secs - 1) < 0.2, "\(secs)s")
        case .failure(let e): check("convert: WAV to M4A keeps the duration", false, "\(e)")
        }
    }

    private static func reminders() {
        let now = Date()
        let a = RemindersService.parse("call mum tomorrow at 9am", now: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        check("reminder: title without the date words", a.title == "call mum", a.title)
        check("reminder: due tomorrow at 9", a.due.map { Calendar.current.isDate($0, inSameDayAs: tomorrow) && Calendar.current.component(.hour, from: $0) == 9 } == true, "\(String(describing: a.due))")
        let b = RemindersService.parse("buy milk")
        check("reminder: no date keeps the whole text", b.title == "buy milk" && b.due == nil)
        let c = RemindersService.parse("  tomorrow  ")
        check("reminder: only a date keeps the text as title", c.title == "tomorrow" && c.due != nil, c.title)
    }

    private static func extras() {
        check("shortcuts: list parsing", ShortcutsService.parseList("Morning\n  Send report \n\nWi-Fi off\n") == ["Morning", "Send report", "Wi-Fi off"])
        let g = WebSearch.resolve("swift concurrency", defaultKey: "duckduckgo")
        check("search: default engine", g?.label == "DuckDuckGo" && g?.url.absoluteString == "https://duckduckgo.com/?q=swift%20concurrency", g?.url.absoluteString ?? "nil")
        check("search: bang picks the engine", WebSearch.resolve("yt lofi beats")?.url.absoluteString == "https://www.youtube.com/results?search_query=lofi%20beats")
        check("search: reserved characters are escaped", WebSearch.resolve("a&b=c#d")?.url.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%23d", WebSearch.resolve("a&b=c#d")?.url.absoluteString ?? "nil")
        check("search: translate", WebSearch.resolve("tr good morning", language: "fr")?.url.absoluteString == "https://translate.google.com/?sl=auto&tl=fr&op=translate&text=good%20morning")
        check("search: a lone bang is a normal query", WebSearch.resolve("yt")?.label == "Google" && WebSearch.resolve("   ") == nil)
        check("search: nine engines", WebSearch.engines.count == 9 && Set(WebSearch.engines.map(\.bang)).count == 9)

        check("network: format", NetworkRate.format(512) == "512 B/s" && NetworkRate.format(1_500) == "1.5 KB/s" && NetworkRate.format(2_300_000) == "2.3 MB/s")
        let a = ["en0": (rx: UInt32.max - 99, tx: UInt32(0))], b = ["en0": (rx: UInt32(100), tx: UInt32(500)), "new": (rx: UInt32(9), tx: UInt32(9))]
        let r = NetworkRate.rate(from: a, to: b, seconds: 2)
        check("network: rate survives counter wrap and ignores new interfaces", r.down == 100 && r.up == 250, "\(r)")
        check("network: counters are readable", !NetworkRate.counters().isEmpty)

        let devs = AudioControl.outputDevices()
        check("audio: output devices listed with names", !devs.isEmpty && devs.allSatisfy { !$0.name.isEmpty }, "\(devs.count)")
        check("audio: the current output is one of them", AudioControl.currentOutput().map { id in devs.contains { $0.id == id } } == true)

        let t = Teleprompter()
        t.script = "x"; t.speed = 60; let before = t.offset
        t.tick(0.5)
        check("teleprompter: scrolls at its speed", t.offset - before == 30, "\(t.offset)")
        t.restart()
        check("teleprompter: restart returns to the top", t.offset == 0)
        UserDefaults.standard.removeObject(forKey: "teleScript"); UserDefaults.standard.removeObject(forKey: "teleSpeed")
    }

    private static func batch3() {
        // Hyper key
        let f = HyperKey.apply(to: [.maskShift])
        check("hyper: adds the four modifiers and keeps existing ones", f.contains([.maskControl, .maskAlternate, .maskShift, .maskCommand]))
        let json = HyperKey.mappingJSON(enabled: true).replacingOccurrences(of: "0x700000039", with: "30064771129").replacingOccurrences(of: "0x70000006D", with: "30064771181")
        let map = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any])?["UserKeyMapping"] as? [[String: Int]]
        check("hyper: Caps Lock maps to F18", map?.first?["HIDKeyboardModifierMappingSrc"] == 0x700000039 && map?.first?["HIDKeyboardModifierMappingDst"] == 0x70000006D, "\(String(describing: map))")
        check("hyper: disabling clears the mapping", HyperKey.mappingJSON(enabled: false) == "{\"UserKeyMapping\":[]}")

        // Menu bar
        check("menu bar: collapsing pushes icons away", MenuBarHider.separatorLength(collapsed: true) > 5_000 && MenuBarHider.separatorLength(collapsed: false) < 20)
        let now = Date()
        check("menu bar calendar: ongoing", MenuBarCalendar.label(title: "Standup", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600), now: now) == L("%@ · now", "Standup"))
        check("menu bar calendar: soon", MenuBarCalendar.label(title: "Standup", start: now.addingTimeInterval(12 * 60 - 5), end: now.addingTimeInterval(3600), now: now) == L("%@ · in %d min", "Standup", 12))
        check("menu bar calendar: long titles are cut", MenuBarCalendar.label(title: String(repeating: "x", count: 40), start: now.addingTimeInterval(300), end: now.addingTimeInterval(900), now: now).count < 40)
        check("menu bar: six tabs can be detached", MenuBarDetach.detachable.count == 6 && !MenuBarDetach.detachable.contains(.terminal))

        // Focus
        let focus = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        check("focus: mode name from the assertions file", FocusMonitor.parse(Data(focus.utf8)) == "Work")
        let dnd = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}"#
        check("focus: Do Not Disturb", FocusMonitor.parse(Data(dnd.utf8)) == L("Do Not Disturb"))
        check("focus: no record means no focus", FocusMonitor.parse(Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)) == nil && FocusMonitor.parse(Data("junk".utf8)) == nil)

        // Notifications: parse a real binary plist and read a real SQLite file
        let plist: [String: Any] = ["app": "com.apple.mail", "req": ["titl": "Alice", "subt": "Re: lunch", "body": "See you at 12"]]
        let blob = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
        let p = NotificationReader.parse(blob)
        check("notifications: parse title, subtitle, body and app", p?.title == "Alice · Re: lunch" && p?.body == "See you at 12" && p?.app == "com.apple.mail", "\(String(describing: p))")
        let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-notif-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_exec(db, "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT); CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB, delivered_date REAL); INSERT INTO app VALUES (1, 'com.apple.mail');", nil, nil, nil)
        var ins: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO record VALUES (7, 1, ?, 1000.0)", -1, &ins, nil)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(ins, 1, $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        sqlite3_step(ins); sqlite3_finalize(ins); sqlite3_close(db)
        let read = NotificationReader.read(path: dbPath)
        check("notifications: read rows from the database", read?.count == 1 && read?.first?.title == "Alice · Re: lunch" && read?.first?.app == "com.apple.mail" && read?.first?.id == 7, "\(String(describing: read))")
        check("notifications: unreadable database gives nil", NotificationReader.read(path: "/nonexistent/db") == nil)

        // Calls
        check("calls: needs a live microphone and a call app", CallMonitor.detect(micLive: true, running: ["com.apple.finder", "us.zoom.xos"]) == "Zoom"
              && CallMonitor.detect(micLive: false, running: ["us.zoom.xos"]) == nil && CallMonitor.detect(micLive: true, running: ["com.apple.finder"]) == nil)

        // Screen
        let r = ScreenGrab.sourceRect(for: CGRect(x: 120, y: 700, width: 300, height: 100), on: CGRect(x: 100, y: 0, width: 1000, height: 900))
        check("screen: AppKit rect to display rect", r == CGRect(x: 20, y: 100, width: 300, height: 100), "\(r)")
        check("window watch: whitespace changes are not changes", !WindowWatch.changed("Build  42%\n", "Build 42%") && WindowWatch.changed("Build 42%", "Build 43%"))
        check("ask: finds links", AskModel.links(in: "docs at https://example.com/x and www.apple.com").count == 2, "\(AskModel.links(in: "docs at https://example.com/x and www.apple.com"))")
        let body = (try? JSONSerialization.jsonObject(with: AskModel.requestBody(text: "hello", question: "what?"))) as? [String: Any]
        let content = ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String) ?? ""
        check("ask: request carries only text, a model and a limit", body?["model"] as? String == "claude-sonnet-5-5" && body?["max_tokens"] as? Int == 1024 && content.contains("hello") && content.contains("what?"))
        check("ask: parses an answer", AskModel.parseAnswer(Data(#"{"content":[{"type":"text","text":"42"},{"type":"text","text":"yes"}]}"#.utf8)) == "42\nyes" && AskModel.parseAnswer(Data("{}".utf8)) == nil)
        let svc = "dev.labs.pillbox.selftest.\(UUID().uuidString)"
        check("keychain: set, get, replace, delete", Keychain.set("k1", svc) && Keychain.get(svc) == "k1" && Keychain.set("k2", svc) && Keychain.get(svc) == "k2" && { Keychain.delete(svc); return Keychain.get(svc) == nil }())

        // Spectrum
        let rate = 48_000.0
        let tone = (0..<1024).map { Float(sin(2 * Double.pi * 1400 * Double($0) / rate)) }
        let levels = Goertzel.levels(tone, sampleRate: rate)
        check("spectrum: a 1.4 kHz tone lights the 1.4 kHz band the most", levels.firstIndex(of: levels.max()!) == 3, "\(levels)")
        check("spectrum: silence is flat", Goertzel.levels([Float](repeating: 0, count: 1024), sampleRate: rate).allSatisfy { $0 == 0 })

        // Gestures
        var d = DoubleTapDetector(); let t0 = Date()
        check("double tap: two quick presses", !d.press(at: t0) && d.press(at: t0.addingTimeInterval(0.2)))
        check("double tap: slow presses do not count, and it resets", !d.press(at: t0.addingTimeInterval(2)) && !d.press(at: t0.addingTimeInterval(3)))
        let first = CGPoint(x: SnapZones.margin + 5, y: SnapZones.margin + 5)
        check("snap zones: tile hit testing", SnapZones.zone(at: first) == .left && SnapZones.zone(at: CGPoint(x: 1, y: 1)) == nil
              && SnapZones.zone(at: CGPoint(x: SnapZones.margin + 2 * (SnapZones.tile.width + SnapZones.gap) + 5, y: SnapZones.margin + 5)) == .full)
        let noon = Date(timeIntervalSince1970: 1_794_052_800)   // 2026-11-07 12:00 UTC
        check("world clock: each zone shows its own time", DesktopWidgetView.time(noon, zone: "Asia/Tokyo") == "21:00" && DesktopWidgetView.time(noon, zone: "America/New_York") == "07:00" && DesktopWidgetView.time(noon, zone: "Europe/London") == "12:00",
              "\(DesktopWidgetView.time(noon, zone: "Asia/Tokyo")) \(DesktopWidgetView.time(noon, zone: "America/New_York"))")
        check("mascot: the plant grows with progress", Mascot.emoji(for: .plant, progress: 0.1) == "🌱" && Mascot.emoji(for: .plant, progress: 0.5) == "🌿" && Mascot.emoji(for: .plant, progress: 0.9) == "🌳" && Mascot.emoji(for: .none, progress: 0.5) == nil)
    }
}

/// `--render <dir>` draws the island states to PNG with ImageRenderer: no screen, no permission.
/// ImageRenderer cannot draw AppKit-backed controls (text fields, pickers), so tabs using them are skipped.
@MainActor
enum ViewRenderer {
    static func run(into dir: String) -> Int32 {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = NotchModel.shared
        model.geometry = NotchGeometry(width: 185, height: 32, screen: nil)
        var ok = true
        func save<V: View>(_ name: String, _ view: V, size: CGSize) {
            let framed = view.frame(width: size.width, height: size.height, alignment: .top)
                .background(Color(white: 0.45)).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: framed); r.scale = 2
            guard let img = r.nsImage, let png = img.pngData() else { print("FAIL  render \(name)"); ok = false; return }
            try? png.write(to: out.appendingPathComponent(name + ".png")); print("wrote \(name).png")
        }
        func island<V: View>(_ v: V, _ size: CGSize) -> some View {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).fill(.black)
                v.foregroundStyle(.white)
            }.frame(width: size.width, height: size.height)
        }
        for tab in [Tab.home, .music, .ai, .shelf] {
            model.tab = tab; model.expanded = true
            save("tab-\(tab.rawValue)", island(ExpandedView(), NotchModel.expandedSize), size: NotchModel.expandedSize)
        }
        model.expanded = false
        let acts = [Activity(symbol: "hammer.fill", title: "Build done", subtitle: "main passed in 42s", tint: .green),
                    Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.6),
                    Activity(symbol: "arrow.down.circle.fill", title: "Download finished", subtitle: "report.pdf", tint: .blue, actionTitle: "Reveal")]
        for (i, a) in acts.enumerated() {
            let size = CGSize(width: 330, height: 66)
            save("activity-\(i)", island(ActivityView(activity: a), size), size: size)
        }
        save("snapzones", SnapZonesView(), size: SnapZones.panelSize)
        save("widgets", DesktopWidgetView(), size: CGSize(width: 330, height: 190))
        let appr = Approval(tool: "Bash", detail: "rm -rf ./build && swift build", respond: { _ in })
        save("approval", island(ApprovalView(approval: appr), CGSize(width: 520, height: 124)), size: CGSize(width: 520, height: 124))
        return ok ? 0 : 1
    }
}

private extension Process {
    static func output(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
