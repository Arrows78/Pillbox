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
        lyrics(); math(); formatting(); clipboard(); stocks(); snapping(); weather(); timer(); usage(); geometry(); stores(); shelf(); palette(); snippets(); watchers(); converter(); reminders(); extras(); batch3(); batch4(); batch5(); batch6(); batch7(); batch8(); awareness(); recordingQRAnnotate(); dictationAndActivity()
        appVolume()
        battery()
        batch9()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    private static func appVolume() {
        let apps = ["com.google.Chrome", "com.google.Chrome.canary", "com.apple.Safari", "com.spotify.client"]
        check("app volume: helpers belong to their app", AppVolumeMath.owner(of: "com.google.Chrome.helper", among: apps) == "com.google.Chrome"
              && AppVolumeMath.owner(of: "com.google.Chrome.canary.helper", among: apps) == "com.google.Chrome.canary"
              && AppVolumeMath.owner(of: "com.spotify.client", among: apps) == "com.spotify.client")
        check("app volume: WebKit audio goes to Safari, strangers to nobody", AppVolumeMath.owner(of: "com.apple.WebKit.GPU", among: apps) == "com.apple.Safari"
              && AppVolumeMath.owner(of: "com.apple.WebKit.GPU", among: ["com.spotify.client"]) == nil && AppVolumeMath.owner(of: "com.google.Chromebook", among: apps) == nil)
        check("app volume: a tap only below 100 % or muted", !AppVolumeMath.needsTap(gain: 1, muted: false) && AppVolumeMath.needsTap(gain: 0.5, muted: false) && AppVolumeMath.needsTap(gain: 1, muted: true))
        check("app volume: channel mapping", AppVolumeMath.source(for: 1, inputs: 2) == 1 && AppVolumeMath.source(for: 1, inputs: 1) == 0 && AppVolumeMath.source(for: 3, inputs: 2) == nil)
        let list = AudioBufferList.allocate(maximumBuffers: 3); defer { free(list.unsafeMutablePointer) }
        let a = UnsafeMutablePointer<Float>.allocate(capacity: 8), b = UnsafeMutablePointer<Float>.allocate(capacity: 4), c = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        defer { a.deallocate(); b.deallocate(); c.deallocate() }
        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 32, mData: a)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: b)
        list[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 16, mData: c)
        let ch = AppVolumeMath.channel(list, from: 1, 1)
        check("app volume: planar and interleaved buffers read alike", AppVolumeMath.channelCount(list, from: 0) == 4 && AppVolumeMath.channelCount(list, from: 1) == 2
              && ch?.0 == c && ch?.1 == 0 && ch?.2 == 1 && ch?.3 == 4 && AppVolumeMath.channel(list, from: 0, 1).map { $0.0 == a && $0.1 == 1 && $0.2 == 2 && $0.3 == 4 } == true
              && AppVolumeMath.channel(list, from: 1, 2) == nil)
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
        // Ten minutes before midnight, "recent" belongs to yesterday: only then is today allowed to be empty.
        check("claude: older entries only in the week", c.week == 165 && (c.today >= 150 || !Calendar.current.isDateInToday(now.addingTimeInterval(-600))), "week \(c.week) today \(c.today)")
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
        check("terminal tab opens at the same size as the others", m.size(hasWings: false) == NotchModel.expandedSize)
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
        clip.query = ""
        clip.items = [ClipItem(text: "hello"), ClipItem(text: "https://apple.com"), ClipItem(text: "#FF8800"), ClipItem(text: "a@b.co"), ClipItem(imageFile: "x.png")]
        let kinds = { (f: ClipFilter) in clip.items.filter(f.matches).count }
        check("clipboard: type filters", kinds(.all) == 5 && kinds(.text) == 2 && kinds(.links) == 1 && kinds(.colors) == 1 && kinds(.images) == 1,
              "\(ClipFilter.allCases.map(kinds))")
        clip.filter = .links
        check("clipboard: the filter applies to the list", clip.filtered.map(\.text) == ["https://apple.com"])
        check("shelf: summary counts items and selection", ShelfService.summary(count: 1, selected: 0) == L("1 item")
              && ShelfService.summary(count: 3, selected: 2) == L("%lld items", 3) + " · " + L("%lld selected", 2))
        check("timer: presets are sorted, none for the stopwatch", TimerService.Mode.allCases.allSatisfy { $0.presets == $0.presets.sorted() }
              && TimerService.Mode.stopwatch.presets.isEmpty && TimerService.Mode.focus.presets.contains(25))
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
        let pw = PrompterText.words("Good morning, everyone, and thanks for joining.")
        check("prompter: words are normalised with their offsets", pw.map(\.word) == ["good", "morning", "everyone", "and", "thanks", "for", "joining"] && pw[1].start == 5)
        check("calendar: finds a Zoom, Meet or Teams link and ignores others",
              MeetingLink.find(in: [nil, "Room 4", "Join https://us02web.zoom.us/j/123?pwd=x now"])?.host == "us02web.zoom.us"
              && MeetingLink.find(in: ["https://example.com/zoom.us"]) == nil)
        let sw = pw.map(\.word)
        check("prompter: voice advances past the words heard", PrompterText.advance(sw, from: 0, heard: ["Good", "morning"]) == 2)
        check("prompter: voice skips ahead when words are dropped", PrompterText.advance(sw, from: 2, heard: ["thanks", "for"]) == 6)
        check("prompter: unrelated speech does not move it", PrompterText.advance(sw, from: 3, heard: ["banana"]) == 3)
        let bar = NotchModel.expandedSize.width - 44 - 10 - 26 - 10 - 20
        let fits = Tab.allCases.allSatisfy { sel in
            let s = TabBarMetrics.split(Tab.allCases, selected: sel, available: bar)
            let w = s.shown.reduce(-TabBarMetrics.spacing) { $0 + TabBarMetrics.spacing + TabBarMetrics.width($1, selected: $1 == sel) } + (s.more.isEmpty ? 0 : TabBarMetrics.spacing + TabBarMetrics.more)
            return w <= bar && s.shown.contains(sel) && s.shown.count + s.more.count == Tab.allCases.count
        }
        check("tab bar: fits the panel for every selected tab, the rest in the menu", fits)
        let wide = TabBarMetrics.split(Tab.allCases, selected: .calendar, available: 5000)
        check("tab bar: everything shows when there is room", wide.more.isEmpty && wide.shown == Tab.allCases)
        check("prompter: speeds map to their nearest preset", PrompterSpeed.nearest(32) == .normal && PrompterSpeed.nearest(100) == .sprint)
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

    private static func batch4() {
        // Shake to open the shelf
        var shake = ShakeDetector(); var t = Date(); var fired = false
        for x in stride(from: 0.0, through: 300.0, by: 20.0) { t += 0.02; if shake.add(CGPoint(x: x, y: 0), at: t) { fired = true } }   // a straight drag
        check("shake: a straight drag is not a shake", !fired)
        shake.reset(); t = Date()
        let zig: [Double] = [0, 70, 0, 70, 0, 70, 0, 70]
        for target in zig { for step in 1...7 { t += 0.02; if shake.add(CGPoint(x: target == 70 ? Double(step) * 10 : 70 - Double(step) * 10, y: 0), at: t) { fired = true } } }
        check("shake: back-and-forth opens the shelf", fired)
        shake.reset(); t = Date(); fired = false
        for target in zig { for step in 1...7 { t += 0.4; if shake.add(CGPoint(x: target == 70 ? Double(step) * 10 : 70 - Double(step) * 10, y: 0), at: t) { fired = true } } }
        check("shake: a slow wander is not a shake", !fired)

        // Break reminders
        var b = BreakLogic(); let start = Date(); var fires = 0
        for m in 0...50 { if b.tick(idle: 2, now: start.addingTimeInterval(Double(m) * 60), every: 20 * 60) { fires += 1 } }
        check("break: reminds every 20 minutes of activity", fires == 2, "\(fires)")
        var c = BreakLogic(); var cf = 0
        for m in 0...50 { if c.tick(idle: m == 15 ? 90 : 2, now: start.addingTimeInterval(Double(m) * 60), every: 20 * 60) { cf += 1 } }
        check("break: an idle minute counts as a break", cf == 1, "\(cf)")

        // Download progress
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pillbox-dl-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir.appendingPathComponent("Movie.mp4.download/inner"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try? Data(count: 5000).write(to: dir.appendingPathComponent("big.zip.crdownload"))
        try? Data(count: 1000).write(to: dir.appendingPathComponent("Movie.mp4.download/inner/part"))
        try? Data(count: 700).write(to: dir.appendingPathComponent("done.pdf"))
        try? Data(count: 10).write(to: dir.appendingPathComponent(".hidden.crdownload"))
        let dl = DownloadScan.scan(dir)
        check("downloads: finds partial files and folders, biggest first, ignores finished and hidden ones", dl == [DownloadItem(name: "big.zip", bytes: 5000), DownloadItem(name: "Movie.mp4", bytes: 1000)], "\(dl)")

        // Build island
        check("build: spots xcodebuild and swift-build in ps output", BuildWatcher.isBuilding(psOutput: "/sbin/launchd\n/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild\n") && BuildWatcher.isBuilding(psOutput: "/usr/bin/swift-build\n"))
        check("build: ignores other processes and look-alikes", !BuildWatcher.isBuilding(psOutput: "/sbin/launchd\n/usr/bin/swift-format\n/Applications/Xcode.app/Contents/MacOS/Xcode\n"))
        let w = BuildWatcher()
        w.update(true, now: Date()); check("build: starts the stopwatch", w.since != nil)
        w.update(false, now: Date().addingTimeInterval(2)); check("build: stops it when the build ends", w.since == nil)

        // Bluetooth batteries
        let bt = #"{"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_batteryLevelLeft":"85%","device_batteryLevelRight":"80%","device_batteryLevelCase":"60%"}},{"Magic Mouse":{"device_batteryLevelMain":"42%"}},{"Keyboard":{"device_address":"x"}}]}]}"#
        let lines = BluetoothBattery.parse(Data(bt.utf8))
        check("bluetooth: AirPods per bud and case, others by main level, no battery means no line", lines == ["AirPods Pro: L 85% · R 80% · Case 60%", "Magic Mouse: 42%"], "\(lines)")
        check("bluetooth: garbage gives nothing", BluetoothBattery.parse(Data("{}".utf8)).isEmpty && BluetoothBattery.parse(Data("x".utf8)).isEmpty)
        _ = BluetoothBattery.read()   // the real system_profiler call must not crash or hang

        // Quick capture
        check("capture: keyword and argument", QuickCapture.argument("event lunch with Sam tomorrow noon", keywords: ["event", "ev"]) == "lunch with Sam tomorrow noon"
              && QuickCapture.argument("ev  x", keywords: ["event", "ev"]) == "x" && QuickCapture.argument("events", keywords: ["event"]) == nil && QuickCapture.argument("event ", keywords: ["event"]) == nil)
        check("capture: AppleScript text is escaped", QuickCapture.appleScriptString("say \"hi\" \\ now") == "\"say \\\"hi\\\" \\\\ now\"" && QuickCapture.appleScriptString("a\nb") == "\"a\" & linefeed & \"b\"", QuickCapture.appleScriptString("say \"hi\" \\ now"))
        // The escaped expression must be valid AppleScript: evaluating it returns the original text.
        let nasty = "quote \" slash \\ end"
        let back = MusicService.run("return \(QuickCapture.appleScriptString(nasty))")?.stringValue
        check("capture: escaped text survives a round trip through AppleScript", back == nasty, back ?? "nil")

        // Display options
        check("display: an unknown display name falls back to automatic", { UserDefaults.standard.set("No Such Display", forKey: "targetDisplay"); defer { UserDefaults.standard.removeObject(forKey: "targetDisplay") }; return NotchGeometry.detect().screen != nil }())
    }

    private static func batch5() {
        // Activity queue
        func a(_ t: String, _ sym: String = "bell") -> Activity { Activity(symbol: sym, title: t) }
        var q = ActivityQueue()
        check("queue: the first island shows at once", q.push(a("A")) && q.current?.title == "A")
        check("queue: a different island waits its turn", !q.push(a("B")) && q.current?.title == "A" && q.pending.count == 1)
        var update = a("A"); update.progress = 0.7
        check("queue: an update of the visible island replaces it in place", q.push(update) && q.current?.progress == 0.7 && q.pending.count == 1)
        var upB = a("B"); upB.progress = 0.2
        _ = q.push(upB)
        check("queue: an update of a waiting island replaces it", q.pending.count == 1 && q.pending[0].progress == 0.2)
        for n in 0..<8 { _ = q.push(a("X\(n)")) }
        check("queue: the backlog is capped, keeping the newest", q.pending.count == ActivityQueue.cap && q.pending.last?.title == "X7", "\(q.pending.map(\.title))")
        let oldest = q.pending.first?.title; q.advance()
        check("queue: advancing shows the oldest waiting island", q.current?.title == oldest && q.pending.count == ActivityQueue.cap - 1, "\(String(describing: q.current?.title)) vs \(String(describing: oldest))")
        var e = ActivityQueue(); _ = e.push(a("Z")); e.advance()
        check("queue: advancing the last island empties it", e.current == nil)
        let m = NotchModel(); m.show(a("One")); m.show(a("Two"))
        check("model: a second island is queued, not shown over the first", m.activity?.title == "One")
        m.dismissActivity()
        check("model: dismissing shows the next one, then nothing", m.activity?.title == "Two")
        m.dismissActivity(); check("model: ... and then nothing", m.activity == nil)

        // Shell actions
        let ok = ActionRunner.runShell("echo hello; echo oops 1>&2")
        check("actions: runs a command and returns its output", ok.status == 0 && ok.output.contains("hello") && ok.output.contains("oops"), "\(ok)")
        check("actions: exit status is reported", ActionRunner.runShell("exit 3").status == 3)
        let t0 = Date(); let slow = ActionRunner.runShell("sleep 20", timeout: 1)
        check("actions: a hung command is killed after the timeout", slow.status == 124 && Date().timeIntervalSince(t0) < 5, "\(slow.status) \(Date().timeIntervalSince(t0))s")
        check("actions: only web and mail links", ActionRunner.url("https://example.com/a")?.host == "example.com" && ActionRunner.url("example.com")?.scheme == "https" && ActionRunner.url("mailto:a@b.co") != nil
              && ActionRunner.url("file:///etc/passwd") == nil && ActionRunner.url("javascript:alert(1)") == nil && ActionRunner.url("ftp://x.y") == nil)
        let st = QuickActionsStore.shared; st.actions = []
        check("actions: valid entries are saved", st.add(name: "Hi", kind: .shell, value: "echo hi") && st.add(name: "Site", kind: .web, value: "example.com") && st.actions.count == 2)
        check("actions: blank or unsafe entries are refused", !st.add(name: " ", kind: .shell, value: "x") && !st.add(name: "Bad", kind: .web, value: "file:///etc/passwd") && !st.add(name: "Empty", kind: .url, value: "") && st.actions.count == 2)
        check("actions: persisted to disk", Store.load("actions.json", as: [QuickAction].self)?.map(\.name) == ["Hi", "Site"])
        st.actions = []

        // Notification island
        let items = [NotificationItem(id: 5, app: "a", title: "old", body: "", date: Date()), NotificationItem(id: 9, app: "a", title: "new2", body: "", date: Date()), NotificationItem(id: 7, app: "a", title: "new1", body: "", date: Date())]
        check("notifications: only entries newer than the last seen, oldest first", NotificationFeed.fresh(items, after: 5).map(\.title) == ["new1", "new2"] && NotificationFeed.fresh(items, after: 9).isEmpty)

        // Pill gestures and theme
        check("pill: unknown or missing settings mean no action", { UserDefaults.standard.set("bogus", forKey: "doubleClickAction"); defer { UserDefaults.standard.removeObject(forKey: "doubleClickAction") }; return PillAction.configured("doubleClickAction") == .none && PillAction.configured("neverSet") == .none }())
        check("pill: every action has a distinct title", Set(PillAction.allCases.map(\.title)).count == PillAction.allCases.count)
        check("theme: four themes, black by default", IslandTheme.allCases.count == 4 && IslandTheme.current == .black)
    }

    private static func batch6() {
        var st = UsageAlertState()
        check("usage alert: silent below the threshold", !st.shouldAlert(percent: 79, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: fires when the threshold is crossed", st.shouldAlert(percent: 81, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: only once per window", !st.shouldAlert(percent: 95, threshold: 80, windowKey: "Codex|1"))
        check("usage alert: a new window can alert again, and so can another provider", st.shouldAlert(percent: 85, threshold: 80, windowKey: "Codex|2") && st.shouldAlert(percent: 85, threshold: 80, windowKey: "Other|2"))

        let json = #"[{"title":"Fix the thing","url":"https://github.com/o/r/pull/7","number":7,"repository":{"nameWithOwner":"o/r"},"isDraft":true},{"title":"No url","number":1,"repository":{"nameWithOwner":"o/r"}},{"title":"Unsafe","url":"javascript:alert(1)","number":2,"repository":{"nameWithOwner":"o/r"}}]"#
        let prs = GitHubPRs.parse(Data(json.utf8))
        check("github: parses a PR and drops entries without an https link", prs == [PullRequest(title: "Fix the thing", repo: "o/r", number: 7, url: "https://github.com/o/r/pull/7", draft: true)], "\(prs)")
        check("github: garbage gives nothing", GitHubPRs.parse(Data("x".utf8)).isEmpty && GitHubPRs.parse(Data("{}".utf8)).isEmpty)
        // The real gh call: when gh is installed and logged in, both queries must answer with a list (possibly empty), not fail.
        if GitHubPRs.tool != nil, ActionRunner.runShell("\(GitHubPRs.tool!) auth status").status == 0 {
            check("github: the real gh queries answer", GitHubPRs.fetch("--author") != nil && GitHubPRs.fetch("--review-requested") != nil)
        }

        check("edge bar: fill follows the level and is clamped", EdgeHUD.fill(for: 0.5, trackHeight: 100) == 50 && EdgeHUD.fill(for: 2, trackHeight: 100) == 100 && EdgeHUD.fill(for: -1, trackHeight: 100) == 0)
        UserDefaults.standard.set("edge", forKey: "hudStyle"); defer { UserDefaults.standard.removeObject(forKey: "hudStyle") }
        let m = NotchModel(); m.show(Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.5))
        check("edge bar: with the edge style a volume change does not take over the island", m.activity == nil)
        m.show(Activity(symbol: "bell", title: "Hello"))
        check("edge bar: other islands still show", m.activity?.title == "Hello")
    }

    private static func batch8() {
        // Palette math must never throw: NSExpression raised an exception on "5+" and crashed the app while typing.
        for bad in ["5+", "(2+3", "2+3)", "*3", "5 6+1", "1..2+3", "()+1", "5%3", "--"] {
            check("palette math: \"\(bad)\" is rejected, not a crash", PaletteModel.evaluate(bad) == nil, PaletteModel.evaluate(bad) ?? "nil")
        }
        check("palette math: unary minus and percent", PaletteModel.evaluate("-2+10") == "8" && PaletteModel.evaluate("200*10%") == "20", "\(PaletteModel.evaluate("-2+10") ?? "nil") \(PaletteModel.evaluate("200*10%") ?? "nil")")
        // Settings backup
        let suite = UserDefaults(suiteName: "pillbox.selftest.backup")!; suite.removePersistentDomain(forName: "pillbox.selftest.backup")
        suite.set(false, forKey: "hoverOpen"); suite.set(0.3, forKey: "hoverDelay"); suite.set("evil", forKey: "devAPIToken"); suite.set(true, forKey: "devAPIEnabled")
        let data = SettingsBackup.data(from: suite)!
        check("backup: leaves the local API switch and token out", { let f = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]; let st = f?["settings"] as? [String: Any]; return st?["devAPIToken"] == nil && st?["devAPIEnabled"] == nil && st?["hoverOpen"] as? Bool == false }())
        let other = UserDefaults(suiteName: "pillbox.selftest.backup2")!; other.removePersistentDomain(forName: "pillbox.selftest.backup2")
        check("backup: restores what it holds", SettingsBackup.restore(data, into: other) == 2 && other.object(forKey: "hoverOpen") as? Bool == false && other.double(forKey: "hoverDelay") == 0.3)
        let hostile: [String: Any] = ["format": "pillbox-settings", "version": 1, "settings": ["hoverDelay": 99.0, "hoverOpen": "yes", "hudStyle": "<script>", "devAPIEnabled": true, "panelScale": 1.1, "searchEngine": "bing"]]
        let hdata = try! PropertyListSerialization.data(fromPropertyList: hostile, format: .xml, options: 0)
        let third = UserDefaults(suiteName: "pillbox.selftest.backup3")!; third.removePersistentDomain(forName: "pillbox.selftest.backup3")
        check("backup: clamps numbers, drops wrong types, unknown values and unlisted keys", SettingsBackup.restore(hdata, into: third) == 3 && third.double(forKey: "hoverDelay") == 0.6 && third.object(forKey: "hoverOpen") == nil && third.object(forKey: "hudStyle") == nil && third.object(forKey: "devAPIEnabled") == nil && third.string(forKey: "searchEngine") == "bing")
        check("backup: a foreign plist is not a backup", SettingsBackup.restore(try! PropertyListSerialization.data(fromPropertyList: ["hoverOpen": true], format: .xml, options: 0), into: third) == nil)
        SettingsBackup.resetAll(in: other)
        check("backup: reset removes every stored setting", other.object(forKey: "hoverOpen") == nil && other.object(forKey: "hoverDelay") == nil)
        for (suite, name) in [(suite, "pillbox.selftest.backup"), (other, "pillbox.selftest.backup2"), (third, "pillbox.selftest.backup3")] { suite.removePersistentDomain(forName: name) }
        // Update check and shortcuts table
        check("update: compares versions numerically", UpdateCheck.isNewer("v0.10.0", than: "0.9.9") && !UpdateCheck.isNewer("0.3.1", than: "0.3.1") && UpdateCheck.isNewer("1.0", than: "0.9.9") && !UpdateCheck.isNewer("0.3", than: "0.3.1"))
        check("update: only offers a github.com https page", UpdateCheck.releasePage(from: ["html_url": "https://github.com/Arrows78/Pillbox/releases/tag/v1"]) != nil && UpdateCheck.releasePage(from: ["html_url": "https://evil.example/x"]) == nil && UpdateCheck.releasePage(from: ["html_url": "http://github.com/x"]) == nil)
        check("shortcuts: every global shortcut has its own id and key", Set(GlobalShortcut.allCases.map(\.rawValue)).count == GlobalShortcut.allCases.count && GlobalShortcut.palette.keycaps == "⌃⌥K")
        check("diagnostics: no home folder or user name", !Diagnostics.text.contains(NSHomeDirectory()) && !Diagnostics.text.contains(NSUserName()))
    }

    private static func batch7() {
        // MCP protocol
        var calls: [(String, [String: Any])] = []
        let call: (String, [String: Any]) -> (ok: Bool, text: String) = { n, a in calls.append((n, a)); return (n != "stop_timer", "ran \(n)") }
        let `init` = MCPServer.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26"]], call: call)
        check("mcp: initialize echoes the protocol version and announces tools", (`init`?["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-03-26" && ((`init`?["result"] as? [String: Any])?["capabilities"] as? [String: Any])?["tools"] != nil)
        check("mcp: a notification gets no answer", MCPServer.handle(["jsonrpc": "2.0", "method": "notifications/initialized"], call: call) == nil)
        let list = MCPServer.handle(["jsonrpc": "2.0", "id": "abc", "method": "tools/list"], call: call)
        let names = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        check("mcp: lists the six tools, and string ids are kept", names.count == 6 && names.contains("start_timer") && list?["id"] as? String == "abc", "\(names)")
        let res = MCPServer.handle(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "start_timer", "arguments": ["minutes": 5]]], call: call)
        check("mcp: a tool call runs the tool and returns its text", calls.last?.0 == "start_timer" && calls.last?.1["minutes"] as? Int == 5 && ((res?["result"] as? [String: Any])?["isError"] as? Bool) == false)
        let bad = MCPServer.handle(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "stop_timer"]], call: call)
        check("mcp: a failing tool is flagged as an error", ((bad?["result"] as? [String: Any])?["isError"] as? Bool) == true)
        let before = calls.count
        let unknown = MCPServer.handle(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "rm_rf"]], call: call)
        check("mcp: an unknown tool is refused and never runs", (unknown?["error"] as? [String: Any])?["code"] as? Int == -32602 && calls.count == before)
        check("mcp: an unknown method is an error", (MCPServer.handle(["jsonrpc": "2.0", "id": 6, "method": "nope"], call: call)?["error"] as? [String: Any])?["code"] as? Int == -32601)
        let cfg = (try? JSONSerialization.jsonObject(with: Data(MCPServer.configuration(executable: "/x/Pillbox").utf8))) as? [String: Any]
        check("mcp: the configuration is valid JSON pointing at --mcp", ((cfg?["mcpServers"] as? [String: Any])?["pillbox"] as? [String: Any])?["args"] as? [String] == ["--mcp"])

        // The API reads until the whole body is there (headers and body can come in separate packets)
        let head = "POST /action HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
        check("api: headers alone are not a request", !DevAPI.completeness(Data(head.utf8)).complete)
        check("api: a partial body is not complete", !DevAPI.completeness(Data((head + "12345").utf8)).complete)
        check("api: the full body completes it, with the right start", DevAPI.completeness(Data((head + "1234567890").utf8)) == (true, head.utf8.count))
        check("api: no Content-Length means no body", DevAPI.completeness(Data("POST /x HTTP/1.1\r\n\r\n".utf8)).complete)
        check("api: no blank line yet is incomplete", !DevAPI.completeness(Data("POST /x HTTP/1.1\r\nContent-Le".utf8)).complete)

        // Agent actions, validated before anything happens
        check("actions: bad arguments are refused", !AgentActions.run("start_timer", ["minutes": 0]).ok && !AgentActions.run("start_timer", [:]).ok && !AgentActions.run("music_control", ["action": "explode"]).ok
              && !AgentActions.run("add_to_shelf", ["path": "/definitely/not/here"]).ok && !AgentActions.run("show_notification", ["title": ""]).ok && !AgentActions.run("nope", [:]).ok)
        let t = TimerService.shared; let ok = AgentActions.run("start_timer", ["minutes": 7])
        check("actions: start_timer sets a countdown and runs it", ok.ok && t.mode == .countdown && t.countdownMinutes == 7 && t.running); _ = AgentActions.run("stop_timer", [:])
        check("actions: stop_timer stops it", !t.running)

        // Turn tokens
        let tr = [#"{"type":"user","message":{"role":"user","content":"first prompt"}}"#,
                  #"{"type":"assistant","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":10,"cache_read_input_tokens":9999}}}"#,
                  #"{"type":"user","message":{"role":"user","content":"second prompt"}}"#,
                  #"{"type":"assistant","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":0}}}"#,
                  #"{"type":"assistant","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":200,"output_tokens":100,"cache_creation_input_tokens":0}}}"#,
                  #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"#,
                  #"{"type":"assistant","requestId":"r3","message":{"id":"m3","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0}}}"#].joined(separator: "\n")
        check("turn: counts only the last prompt's turn, once per message, without cache reads, across tool results", AgentTurn.tokens(in: tr) == 300 + 15, "\(AgentTurn.tokens(in: tr))")
        check("turn: an empty transcript is zero", AgentTurn.tokens(in: "") == 0)
        let home = NSHomeDirectory()
        check("turn: only .jsonl under ~/.claude are readable", AgentTurn.isAllowed(home + "/.claude/projects/x/s.jsonl") && !AgentTurn.isAllowed("/etc/passwd") && !AgentTurn.isAllowed(home + "/.claude/../.ssh/id_rsa.jsonl") && !AgentTurn.isAllowed(home + "/.claude/settings.json"))

        // Panel size
        UserDefaults.standard.set(1.3, forKey: "panelScale"); defer { UserDefaults.standard.removeObject(forKey: "panelScale") }
        let m = NotchModel(); m.expanded = true
        check("panel: scales the open size", abs(m.size(hasWings: false).width - NotchModel.expandedSize.width * 1.3) < 0.01)
        UserDefaults.standard.set(9.0, forKey: "panelScale")
        check("panel: the scale is clamped", NotchModel.scale == 1.3)
        UserDefaults.standard.set(0.1, forKey: "panelScale")
        check("panel: ... on both sides", NotchModel.scale == 0.8)
        check("panel: the largest panel fits its window", NotchModel.baseExpanded(.terminal).width * 1.3 <= NotchModel.windowSize.width && NotchModel.baseExpanded(.terminal).height * 1.3 <= NotchModel.windowSize.height)

        // Floating player and lyrics
        check("player: swipe left is next, right is previous", swipeAction(dx: -80, dy: 5) == .next && swipeAction(dx: 80, dy: -5) == .previous)
        check("player: short or vertical drags do nothing", swipeAction(dx: -30, dy: 0) == nil && swipeAction(dx: 60, dy: 80) == nil)
        check("player: four sizes, growing", PlayerSize.allCases.map(\.rawValue) == PlayerSize.allCases.map(\.rawValue).sorted() && PlayerSize.allCases.count == 4)
        let ls = [LyricLine(time: 1, text: "a"), LyricLine(time: 5, text: "b"), LyricLine(time: 9, text: "c")]
        check("lyrics: the current line follows the playback position", LyricsScreenView.currentIndex(ls, at: 0) == nil && LyricsScreenView.currentIndex(ls, at: 5.5) == 1 && LyricsScreenView.currentIndex(ls, at: 99) == 2)

        let env = TerminalSession.sanitized(["PATH=/usr/bin", "PWD=/somewhere", "OLDPWD=/else", "CLAUDE_PROJECT_DIR=/proj", "TERM=xterm", "INIT_CWD=/x"], home: "/Users/me")
        check("terminal: inherited directory variables are dropped and PWD is the home folder", env.sorted() == ["PATH=/usr/bin", "PWD=/Users/me", "TERM=xterm"], "\(env)")

        check("equalizer: real levels set the bar, a wave otherwise, and both stay in range",
              Equalizer.barHeight(index: 0, time: 0, levels: [0, 1, 0, 0, 0, 0]) == 16 && Equalizer.barHeight(index: 0, time: 0, levels: [0, 0, 0, 0, 0, 0]) == 3
              && (5...16).contains(Equalizer.barHeight(index: 2, time: 1.7, levels: nil)))

        // Copy stack and calculation history
        var st = CopyStack(); st.push("one"); st.push("two"); st.push("three")
        check("stack: pastes in the order of copying", st.pop() == "one" && st.pop() == "two" && st.items == ["three"])
        var big = CopyStack(); for n in 0..<(CopyStack.cap + 5) { big.push("\(n)") }
        check("stack: capped, dropping the oldest", big.items.count == CopyStack.cap && big.items.first == "5")
        check("stack: empty gives nil", { var e = CopyStack(); return e.pop() == nil }())
        var h = CalcHistory(); h.add(expression: "2+2", result: "4"); h.add(expression: "3*3", result: "9"); h.add(expression: "2+2", result: "4")
        check("calc history: newest first, no duplicates", h.entries == ["2+2 = 4", "3*3 = 9"], "\(h.entries)")
        for n in 0..<15 { h.add(expression: "\(n)+1", result: "\(n + 1)") }
        check("calc history: capped", h.entries.count == CalcHistory.cap)
        check("calc history: gets the result back", CalcHistory.result(of: "2+2 = 4") == "4")
    }

    private static func awareness() {
        let now = Date(), apps: Set<String> = ["com.hnc.Discord"]
        check("focus guard: blocks a listed app only while a Focus timer runs",
              FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: false, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .rest, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .stopwatch, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: "com.apple.Safari", blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now)
              && !FocusGuard.shouldBlock(bundleID: nil, blocked: apps, mode: .focus, running: true, allowedUntil: [:], now: now))
        check("focus guard: Allow 5 min lets it through until the allowance ends",
              !FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: ["com.hnc.Discord": now.addingTimeInterval(60)], now: now)
              && FocusGuard.shouldBlock(bundleID: "com.hnc.Discord", blocked: apps, mode: .focus, running: true, allowedUntil: ["com.hnc.Discord": now.addingTimeInterval(-1)], now: now))
        let fs: [String: Any] = ["ManagedSpaceID": 40, "type": 4, "TileLayoutManager": ["TileSpaces": [["appName": "Safari"]]]]
        let displays: [[String: Any]] = [["Spaces": [["ManagedSpaceID": 1, "type": 0], fs, ["ManagedSpaceID": 7, "type": 0], ["ManagedSpaceID": 41, "type": 4]]],
                                         ["Spaces": [["ManagedSpaceID": 90, "type": 0], ["ManagedSpaceID": 91, "type": 0]]]]
        check("spaces: desktops are numbered per display, skipping full-screen spaces",
              SpaceInfo.kind(displays: displays, active: 7) == .desktop(2) && SpaceInfo.kind(displays: displays, active: 1) == .desktop(1) && SpaceInfo.kind(displays: displays, active: 91) == .desktop(2))
        check("spaces: a full-screen space is named after its app, unknown ids give nothing",
              SpaceInfo.kind(displays: displays, active: 40) == .fullScreen("Safari") && SpaceInfo.kind(displays: displays, active: 41) == .fullScreen(nil) && SpaceInfo.kind(displays: displays, active: 5) == nil && SpaceInfo.kind(displays: [], active: 1) == nil)
        check("spaces: labels", SpaceInfo.label(.desktop(3), frontApp: "X") == L("Desktop %d", 3) && SpaceInfo.label(.fullScreen(nil), frontApp: "Keynote") == "Keynote"
              && SpaceInfo.label(.fullScreen("Safari"), frontApp: "Keynote") == "Safari" && SpaceInfo.label(.fullScreen(nil), frontApp: nil) == L("Full screen"))
        check("camera guard: never for Pillbox's own mirror", CameraGuard.island(mirrorOpen: true, frontName: "Zoom", frontBundle: "us.zoom.xos", own: "dev.labs.pillbox") == nil)
        check("camera guard: names the front app, but not Pillbox itself",
              CameraGuard.island(mirrorOpen: false, frontName: "Zoom", frontBundle: "us.zoom.xos", own: "dev.labs.pillbox") == .some("Zoom")
              && CameraGuard.island(mirrorOpen: false, frontName: "Pillbox", frontBundle: "dev.labs.pillbox", own: "dev.labs.pillbox") == .some(nil))
    }

    private static func recordingQRAnnotate() {
        let big = ScreenRecorder.outputSize(width: 6016, height: 3384), odd = ScreenRecorder.outputSize(width: 1001, height: 501)
        check("recording: big displays fit H.264, keeping the ratio, in even sizes", big.width <= 4096 && big.height <= 2304 && big.width % 2 == 0 && big.height % 2 == 0 && abs(Double(big.width) / Double(big.height) - 6016.0 / 3384) < 0.01, "\(big)")
        check("recording: small sizes are only rounded to even", odd == (1000, 500), "\(odd)")
        let name = ScreenRecorder.fileName(at: Date(timeIntervalSince1970: 0))
        check("recording: a dated .mov name", name.hasSuffix(".mov") && name.contains("19") && !name.contains("/") && !name.contains(":"), name)

        check("qr: web links open, anything else is only copied", QRReader.webLink(" https://example.com/a?b=1 ") != nil && QRReader.webLink("HTTP://x.org") != nil
              && QRReader.webLink("javascript:alert(1)") == nil && QRReader.webLink("example.com") == nil && QRReader.webLink("WIFI:S:home;T:WPA;P:x;;") == nil && QRReader.webLink("https://") == nil)
        let payload = "https://example.com/pillbox?q=42"
        if let f = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(payload.utf8), "inputCorrectionLevel": "M"]), let out = f.outputImage {
            let img = CIContext().createCGImage(out.transformed(by: CGAffineTransform(scaleX: 12, y: 12)).composited(over: CIImage(color: .white).cropped(to: CGRect(x: -40, y: -40, width: 400, height: 400))), from: CGRect(x: -40, y: -40, width: 400, height: 400))
            let codes = img.map(QRReader.decode) ?? []
            check("qr: a generated QR code is decoded", codes == [payload], "\(codes)")
        } else { check("qr: the generator exists", false) }

        check("annotate: images only", Annotator.canAnnotate(URL(fileURLWithPath: "/a/Shot.PNG")) && Annotator.canAnnotate(URL(fileURLWithPath: "/a/b.heic")) && !Annotator.canAnnotate(URL(fileURLWithPath: "/a/b.pdf")))
        check("annotate: the copy sits next to the original", Annotator.outputURL(for: URL(fileURLWithPath: "/a/My shot.jpg")).path == "/a/My shot annotated.png")
        let red = NSColor.systemRed.usingColorSpace(.sRGB)!.cgColor
        let ctx = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<200 { ctx.setFillColor(x % 2 == 0 ? .black : .white); ctx.fill(CGRect(x: x, y: 0, width: 1, height: 100)) }
        let base = ctx.makeImage()!
        func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> [UInt8] {   // y from the top
            let c = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
            let p = c.data!.assumingMemoryBound(to: UInt8.self); return [p[0], p[1], p[2]]
        }
        let marks = [Mark(kind: .rect, color: red, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)]),
                     Mark(kind: .pixelate, color: red, points: [CGPoint(x: 100, y: 0), CGPoint(x: 200, y: 100)]),
                     Mark(kind: .text, color: red, points: [CGPoint(x: 5, y: 60)], text: "Hi"),
                     Mark(kind: .arrow, color: red, points: [CGPoint(x: 70, y: 90), CGPoint(x: 95, y: 60)])]
        let out = Annotator.render(base, marks: marks, pixelated: Annotator.pixelated(base))
        check("annotate: the render keeps the size", out?.width == 200 && out?.height == 100)
        if let out {
            let edge = pixel(out, 10, 25)
            check("annotate: a rectangle is drawn where it was put (top-left origin)", edge[0] > 200 && edge[1] < 120, "\(edge)")
            let a = pixel(out, 150, 50), b = pixel(out, 151, 50)
            check("annotate: pixelate flattens the stripes", abs(Int(a[0]) - Int(b[0])) < 40, "\(a) \(b)")
            check("annotate: the rest of the picture is untouched", pixel(out, 90, 5) == [0, 0, 0] && pixel(out, 91, 5) == [255, 255, 255], "\(pixel(out, 90, 5))")
        }
        check("annotate: arrows have a head, a zero-length arrow draws nothing",
              Annotator.paths(marks[3], lineWidth: 3).fill != nil && Annotator.paths(Mark(kind: .arrow, color: red, points: [.zero, .zero]), lineWidth: 3).stroke == nil)
    }

    private static func dictationAndActivity() {
        var t = DictationText(); t.update("hello", finished: false); t.update("hello world", finished: true); t.update("again", finished: false)
        check("dictation: text survives the recogniser's restarts", t.full == "hello world again", t.full)
        t.update("", finished: true)
        check("dictation: a request ending in an error keeps what it heard", t.full == "hello world again" && t.partial.isEmpty, t.full)
        check("dictation: nothing heard is empty", DictationText().full.isEmpty)
        check("dictation: level meter stays in range", SpeechListener.level(UnsafeBufferPointer(start: nil, count: 0)) == 0
              && [Float](repeating: 1, count: 64).withUnsafeBufferPointer { SpeechListener.level($0) } == 1
              && [Float](repeating: 0.001, count: 64).withUnsafeBufferPointer { SpeechListener.level($0) } < 0.5)
        check("dictation: its shortcut is opt-in", GlobalShortcut.dictate.setting == "dictationShortcut" && GlobalShortcut.palette.isEnabled && GlobalShortcut.dictate.keycaps == "⌃⌥D")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = { (d: Int, h: Int) in cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h))! }
        var log = ActivityLog()
        log.add(keys: 10, clicks: 2, metres: 1.5, on: day(1, 23), calendar: cal)
        log.add(keys: 5, clicks: 1, metres: 0.5, on: day(1, 23), calendar: cal)
        log.add(keys: 7, clicks: 0, metres: 0, on: day(2, 0), calendar: cal)
        check("activity: counts add up within a day and roll over at midnight", log.days.count == 2 && log.days[0] == ActivityDay(day: "2026-03-01", keys: 15, clicks: 3, metres: 2) && log.days[1].keys == 7, "\(log.days)")
        for d in 3...12 { log.add(keys: d, clicks: 0, metres: 0, on: day(d, 12), calendar: cal) }
        check("activity: only the last 7 days are kept, oldest first", log.days.map(\.day) == (6...12).map { String(format: "2026-03-%02d", $0) }, "\(log.days.map(\.day))")
        let week = log.lastWeek(ending: day(14, 9), calendar: cal)
        check("activity: the week fills days without activity with zeros", week.count == 7 && week.first?.day == "2026-03-08" && week.last == ActivityDay(day: "2026-03-14") && week[4].keys == 12, "\(week)")
        check("activity: today's counts", log.today(day(12, 18), calendar: cal).keys == 12 && log.today(day(20, 1), calendar: cal).keys == 0)
        check("activity: the week crosses month ends", ActivityLog.week(ending: day(2, 8), calendar: cal).first == "2026-02-24")
        let mm = ActivityCounter.millimetresPerPoint(physicalWidth: 300, pointWidth: 1500)
        check("activity: points become millimetres from the screen's physical size", abs(mm - 0.2) < 1e-9 && ActivityCounter.millimetresPerPoint(physicalWidth: 0, pointWidth: 1500) == ActivityCounter.fallbackMillimetresPerPoint)
        check("activity: 500 points at 0.2 mm/pt is 10 cm", abs(ActivityCounter.metres(from: .zero, to: CGPoint(x: 3000, y: 4000).applying(.init(scaleX: 0.1, y: 0.1)), mmPerPoint: 0.2) - 0.1) < 1e-9)
        check("activity: a warp between screens is not travel", ActivityCounter.metres(from: .zero, to: CGPoint(x: 5000, y: 0), mmPerPoint: 0.2) == 0)
        let back = try? JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(log))
        check("activity: the log round-trips through JSON", back == log)
    }
}

extension SelfTest {
    static func battery() {
        let now = Date()
        func at(_ min: Double, _ level: Int, _ ch: Bool = false) -> BatterySample { BatterySample(t: now.addingTimeInterval(-min * 60), level: level, charging: ch) }
        let h = BatteryMath.trimmed([at(10, 50), at(49 * 60, 90), at(5, 49), at(47 * 60, 80), at(-30, 10)], now: now)
        check("battery history: keeps 48 h, oldest first, drops the future", h.map(\.level) == [80, 50, 49], "\(h.map(\.level))")
        check("battery drain: points lost per 10 min off the charger", BatteryMath.drainPer10Min([at(12, 60), at(6, 57), at(0, 54)], now: now) == 5)
        check("battery drain: only the run since unplugging counts", BatteryMath.drainPer10Min([at(14, 40, true), at(10, 60), at(0, 55)], now: now) == 5)
        check("battery drain: too little data or charging gives nil", BatteryMath.drainPer10Min([at(3, 60), at(0, 55)], now: now) == nil && BatteryMath.drainPer10Min([at(12, 50, true), at(0, 60, true)], now: now) == nil)
        check("battery health: Apple Silicon raw mAh, Intel mAh, percentage alone, capped at 100",
              BatteryMath.healthPercent(rawMax: 4_600, max: 100, design: 5_000) == 92 && BatteryMath.healthPercent(rawMax: nil, max: 4_000, design: 5_000) == 80
              && BatteryMath.healthPercent(rawMax: nil, max: 88, design: nil) == 88 && BatteryMath.healthPercent(rawMax: 5_200, max: 100, design: 5_000) == 100
              && BatteryMath.healthPercent(rawMax: nil, max: nil, design: nil) == nil)
        check("battery: time remaining as h:mm, nil while unknown", BatteryMath.remaining(12_000) == "3:20" && BatteryMath.remaining(-1) == nil && BatteryMath.remaining(59) == "0:00")
        let sp = BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_battery_charge_info":{}},{"sppower_battery_health_info":{"sppower_battery_cycle_count":412,"sppower_battery_health_maximum_capacity":"87 %"}}]}"#.utf8))
        check("battery health: read from System Information as Settings shows it", sp?.percent == 87 && sp?.cycles == 412)
        check("battery health: a desktop report gives nil", BatteryHealth.parse(Data(#"{"SPPowerDataType":[{"sppower_ac_charger_information":{}}]}"#.utf8)) == nil)
        _ = BatteryHealth.registry(); _ = BatteryHealth.hasBattery()   // real IOKit reads must not crash, with or without a battery   // real IOKit reads must not crash, with or without a battery
        var net: [NetSample] = []
        for i in 0..<400 { net = NetworkRate.appending(net, NetSample(t: now.addingTimeInterval(Double(i * 2)), down: Double(i), up: 0)) }
        check("network history: keeps the last 10 minutes", net.count == 301 && net.first?.down == 99, "\(net.count)")
        check("bluetooth island: AirPods symbol and battery line", BluetoothIslands.symbol(for: "Tom's AirPods Pro") == "airpodspro" && BluetoothIslands.symbol(for: "WH-1000XM5") == "headphones"
              && BluetoothIslands.battery(of: "AirPods Pro", in: ["AirPods Pro: L 85% · R 80%", "Magic Mouse: 42%"]) == "L 85% · R 80%" && BluetoothIslands.battery(of: "AirPods", in: ["AirPods Pro: L 1%"]) == nil)
    }
}

/// `--render <dir>` draws the island states to PNG from an offscreen window: no permission needed.
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
            // Drawn by a real hosting view in an offscreen window: AppKit-backed controls (fields, menus) render too.
            let host = NSHostingView(rootView: framed)
            let win = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
            win.contentView = host; win.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("FAIL  render \(name)"); ok = false; return }
            host.cacheDisplay(in: host.bounds, to: rep); win.orderOut(nil)
            guard let png = rep.representation(using: .png, properties: [:]) else { print("FAIL  render \(name)"); ok = false; return }
            try? png.write(to: out.appendingPathComponent(name + ".png")); print("wrote \(name).png")
        }
        func island<V: View>(_ v: V, _ size: CGSize) -> some View {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28).fill(.black)
                v.foregroundStyle(.white)
            }.frame(width: size.width, height: size.height)
        }
        // Drawn under a real 32 pt notch, so the header takes the room it takes on a MacBook.
        model.geometry = NotchGeometry(width: 185, height: 32, notch: true)
        for tab in Tab.allCases where tab != .terminal {
            model.tab = tab; model.expanded = true
            let size = NotchModel.baseExpanded(tab)
            save("tab-\(tab.rawValue)", island(ExpandedView(), size), size: size)
        }
        let mixer = AppVolumeService.shared
        mixer.preview = true
        mixer.apps = [AppAudio(id: "com.spotify.client", name: "Spotify", icon: nil, processes: [], playing: true),
                      AppAudio(id: "com.google.Chrome", name: "Google Chrome with a long name", icon: nil, processes: [], playing: true),
                      AppAudio(id: "com.apple.Safari", name: "Safari", icon: nil, processes: [], playing: true),
                      AppAudio(id: "us.zoom.xos", name: "zoom.us", icon: nil, processes: [], playing: true)]
        mixer.showing = true; model.tab = .music
        save("tab-music-mixer", island(ExpandedView(), NotchModel.expandedSize), size: NotchModel.expandedSize)
        mixer.showing = false; mixer.apps = []; mixer.preview = false
        model.expanded = false
        let acts = [Activity(symbol: "hammer.fill", title: "Build done", subtitle: "main passed in 42s", tint: .green),
                    Activity(symbol: "speaker.wave.2.fill", title: "Volume", progress: 0.6),
                    Activity(symbol: "arrow.down.circle.fill", title: "Download finished", subtitle: "report.pdf", tint: .blue, actionTitle: "Reveal")]
        for (i, a) in acts.enumerated() {
            let size = CGSize(width: 330, height: 66)
            save("activity-\(i)", island(ActivityView(activity: a), size), size: size)
        }
        ScreenRecorder.shared.since = Date(timeIntervalSinceNow: -75)
        save("recording-wings", island(CollapsedWings(), model.size(hasWings: true)), size: model.size(hasWings: true))
        model.tab = .shelf; model.expanded = true
        save("recording-panel", island(ExpandedView(), NotchModel.expandedSize), size: NotchModel.expandedSize)
        model.expanded = false; ScreenRecorder.shared.since = nil
        let qr = Activity(symbol: "qrcode", title: "QR code link", subtitle: "https://example.com/a%20b?q=1", tint: .green, actionTitle: "Open link")
        save("activity-qr", island(ActivityView(activity: qr), CGSize(width: 330, height: 66)), size: CGSize(width: 330, height: 66))
        let hist = (0..<288).map { i in BatterySample(t: Date().addingTimeInterval(Double(i - 287) * 300), level: 20 + abs(i % 120 - 60), charging: i % 120 > 100) }
        let gaugeArea = CGSize(width: 280, height: 76)   // the gauge row it replaces on Home
        save("battery-chart", island(BatteryChartCard(samples: hist, level: 64, remaining: "3:20", health: (92, 312)), gaugeArea), size: gaugeArea)
        let net = (0..<300).map { i in NetSample(t: Date().addingTimeInterval(Double(i - 299) * 2), down: abs(sin(Double(i) / 9)) * 2e6, up: abs(cos(Double(i) / 13)) * 4e5) }
        save("network-sparkline", VStack(alignment: .leading) {   // the 190 pt left column of Home, typical and worst case
            NetworkLine(down: 1_500_000, up: 512, samples: net); NetworkLine(down: 999_900_000, up: 999_900_000, samples: net)
        }.frame(width: 190, alignment: .leading).background(.black), size: CGSize(width: 190, height: 34))
        save("battery-chart-empty", island(BatteryChartCard(samples: [], level: 100, health: nil, hasBattery: false), gaugeArea), size: gaugeArea)
        save("snapzones", SnapZonesView(), size: SnapZones.panelSize)
        save("widgets", DesktopWidgetView(), size: CGSize(width: 330, height: 190))
        let appr = Approval(tool: "Bash", detail: "rm -rf ./build && swift build", respond: { _ in })
        save("approval", island(ApprovalView(approval: appr), CGSize(width: 520, height: 124)), size: CGSize(width: 520, height: 124))
        let aw = [Activity(symbol: SpaceWatcher.symbol, title: L("Desktop %d", 3), tint: .cyan),
                  Activity(symbol: "hand.raised.fill", title: L("Blocked while focusing"), subtitle: "Discord", tint: .orange, image: BlockedAppsStore.bitmap(NSWorkspace.shared.icon(forFile: "/System/Applications/Messages.app")), actionTitle: L("Allow 5 min")),
                  Activity(symbol: "video.fill", title: L("Camera turned on"), subtitle: L("Probably %@", "Microsoft Teams (work or school)"), tint: .green)]
        for (i, a) in aw.enumerated() { save("awareness-\(i)", island(ActivityView(activity: a), CGSize(width: 330, height: 66)), size: CGSize(width: 330, height: 66)) }
        let dic = DictationService.shared
        dic.text = DictationText(); dic.forceActive(true)
        let dsize = model.size(hasWings: false)
        save("dictation-empty", island(DictationView(), dsize), size: dsize)
        dic.text.update("Remind me to send the quarterly report to the whole team before Friday noon", finished: false)
        dic.meter.level = 0.7
        save("dictation-text", island(DictationView(), dsize), size: dsize)
        dic.forceActive(false)
        var demo = ActivityLog()
        for (i, n) in [3200, 5400, 800, 0, 6100, 4700, 2900].enumerated() {
            demo.add(keys: n, clicks: n / 6, metres: Double(n) / 20, on: Calendar.current.date(byAdding: .day, value: i - 6, to: Date())!)
        }
        ActivityCounter.shared.preview(demo)
        for (i, a) in [Activity(symbol: "chart.bar.fill", title: L("%@ keys · %@ clicks", 12_345.formatted(), 2_345.formatted()), subtitle: L("%@ of mouse travel", ActivityCounter.distance(1234)), tint: .cyan),
                       Activity(symbol: "chart.bar.fill", title: "Activity counter is off", tint: .orange, actionTitle: "Turn on"),
                       Activity(symbol: "mic.slash.fill", title: "Microphone needed", subtitle: "Also allow speech recognition", tint: .orange, actionTitle: "Settings")].enumerated() {
            let size = CGSize(width: 330, height: 66)
            save("activity-today-\(i)", island(ActivityView(activity: a), size), size: size)
        }
        save("activity-card", ActivityCounterCard().background(Color(white: 0.12)), size: CGSize(width: 530, height: 90))
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

extension SelfTest {
    /// Custom tabs and the features that came with 0.6.
    static func batch9() {
        check("tabs: hidden set parses, ignores unknown names and never hides Home",
              Tab.hidden(from: "music,home,bogus,terminal") == [.music, .terminal] && Tab.hidden(from: nil).isEmpty && Tab.hidden(from: "") .isEmpty)
        var q = ActivityQueue()
        _ = q.push(Activity(symbol: "speaker.wave.2.fill", title: "Volume", priority: .low))
        let shownHigh = q.push(Activity(symbol: "phone.fill", title: "In a call", priority: .high))
        let shownLow = q.push(Activity(symbol: "capslock", title: "Caps Lock on", priority: .low))
        _ = q.push(Activity(symbol: "bell", title: "Later")); _ = q.push(Activity(symbol: "battery.0", title: "Low battery", priority: .high))
        check("activity queue: high replaces a HUD and jumps the queue, low is dropped when busy",
              shownHigh && q.current?.title == "In a call" && !shownLow && q.pending.map(\.title) == ["Low battery", "Later"])
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:a1\r
        SUMMARY:Team sync\\, weekly\r
        DTSTART;TZID=Europe/Paris:20260211T090000\r
        DTEND;TZID=Europe/Paris:20260211T093000\r
        LOCATION:https://meet.google.com/abc-defg-hij\r
        DESCRIPTION:Long\r
          folded line\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Holiday\r
        DTSTART;VALUE=DATE:20260212\r
        END:VEVENT\r
        END:VCALENDAR
        """
        let ev = ICSParser.parse(ics)
        var paris = Calendar(identifier: .gregorian); paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        check("ics: events, time zones, all-day, escaping and folding", ev.count == 2 && ev[0].title == "Team sync, weekly" && paris.component(.hour, from: ev[0].start) == 9
              && ev[0].end.timeIntervalSince(ev[0].start) == 1800 && ev[0].notes == "Long folded line" && ev[1].allDay && ev[1].end.timeIntervalSince(ev[1].start) == 86400
              && MeetingLink.find(in: [ev[0].location]) != nil, "\(ev)")
        check("ics: webcal links become https, others refused", ICSFeeds.url("webcal://example.com/a.ics")?.scheme == "https" && ICSFeeds.url("file:///etc/passwd") == nil && ICSFeeds.url("nonsense") == nil)
        let safari = VideoSpeed.script(rate: 1.5, bundleID: "com.apple.Safari") ?? ""
        let chrome = VideoSpeed.script(rate: 2, bundleID: "com.google.Chrome") ?? ""
        check("video speed: Safari and Chromium scripts set the rate, other apps get none",
              safari.contains("front document") && safari.contains("playbackRate = 1.5") && chrome.contains("active tab") && chrome.contains("playbackRate = 2.0")
              && VideoSpeed.script(rate: 1, bundleID: "com.apple.finder") == nil, "\(safari)")
        let movedTo = WindowDrag.moved(CGPoint(x: 100, y: 100), by: 10, 20), resizedTo = WindowDrag.resized(CGSize(width: 300, height: 200), by: -500, 10)
        check("window drag: moving up on screen lowers the top-left origin, sizes keep a minimum",
              movedTo == CGPoint(x: 110, y: 80) && resizedTo == CGSize(width: 200, height: 210), "\(movedTo) \(resizedTo)")
        let ddc = ExternalBrightness.packet(percent: 50)
        let checksum: UInt8 = 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 50
        check("ddc: brightness packet is 0x84 0x03 0x10 with the value and a checksum over both addresses",
              ddc == [0x84, 0x03, 0x10, 0x00, 50, checksum] && ExternalBrightness.packet(percent: 250)[4] == 100, "\(ddc)")
        check("notifications: apps listed once, most recent first", NotificationsTab.apps(in: [NotificationItem(id: 3, app: "b", title: "", body: "", date: Date()), NotificationItem(id: 2, app: "a", title: "", body: "", date: Date()), NotificationItem(id: 1, app: "b", title: "", body: "", date: Date())]) == ["b", "a"])
        // Typed as JSON would arrive: the numbers stay Int and Double, not one inferred Double.
        let premium: [String: Any] = ["entitlement": 300, "remaining": 90, "percent_remaining": 30.0]
        let copilot = AIUsageService.copilotUsage(from: ["quota_snapshots": ["premium_interactions": premium] as [String: Any], "quota_reset_date": "2026-12-01"])
        check("copilot: quota becomes a monthly limit", copilot?.limitPercent == 70 && copilot?.today == 210 && copilot?.limitResetsAt != nil && AIUsageService.copilotUsage(from: [:]) == nil,
              "\(String(describing: copilot?.limitPercent)) \(String(describing: copilot?.today)) \(String(describing: copilot?.limitResetsAt))")
        check("verification codes: found next to a keyword, bare codes, never prices or years",
              NotificationFeed.verificationCode(in: "Your verification code is 482913") == "482913" && NotificationFeed.verificationCode(in: "G-123456 is your Google code") == "123456"
              && NotificationFeed.verificationCode(in: "Code: 123 456") == "123456" && NotificationFeed.verificationCode(in: "2048") == "2048"
              && NotificationFeed.verificationCode(in: "Your order of 12.99 shipped in 2026") == nil && NotificationFeed.verificationCode(in: "See you at 1830") == nil)
        let json: [String: Any] = ["tag_name": "v1.2.0", "html_url": "https://github.com/Arrows78/Pillbox/releases/tag/v1.2.0",
                                   "assets": [["name": "Pillbox-1.2.0.zip", "browser_download_url": "https://github.com/Arrows78/Pillbox/releases/download/v1.2.0/Pillbox-1.2.0.zip"],
                                              ["name": "Pillbox-1.2.0.zip.sha256", "browser_download_url": "http://evil.example/x.sha256"]]]
        let rel = Updater.release(from: json)
        check("updater: release parsing keeps https github assets only", rel?.version == "1.2.0" && rel?.zip?.lastPathComponent == "Pillbox-1.2.0.zip" && rel?.sha == nil && rel?.page != nil)
        check("updater: shasum line digest and SHA-256", Updater.digest(in: "ab" + String(repeating: "cd", count: 31) + "  Pillbox.zip\n")?.count == 64 && Updater.digest(in: "short  x") == nil
              && Updater.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        check("updater: due once a day when enabled", Updater.due(enabled: true, last: nil, now: Date()) && !Updater.due(enabled: false, last: nil, now: Date())
              && Updater.due(enabled: true, last: Date().addingTimeInterval(-90000), now: Date()) && !Updater.due(enabled: true, last: Date().addingTimeInterval(-3600), now: Date()))
        check("brew: outdated names parsed, chatter skipped", BrewUpdates.parse("==> Checking\nnode\n  git \nWarning: x\n") == ["node", "git"] && BrewUpdates.parse("").isEmpty)
        let clip = ClipboardService.shared; clip.items = [ClipItem(text: "kept")]
        let merged = ClipboardImport.merge([("kept", Date(), false), ("new one", Date(timeIntervalSince1970: 1), true), ("  ", Date(), false)], into: clip)
        check("clipboard import: new texts added with their date and pin, duplicates and blanks skipped", merged == 1 && clip.items.count == 2 && clip.items.last?.pinned == true && clip.items.last?.date == Date(timeIntervalSince1970: 1))
        clip.items = []
        let key = KeySynth.sample(.thock, kind: .press), n = Int(key.frameLength), samples = (0..<n).map { key.floatChannelData![0][$0] }
        check("typing sounds: a synthesised key is finite, audible and within range", n > 1000 && samples.allSatisfy { $0.isFinite && abs($0) <= 1 } && (samples.map { abs($0) }.max() ?? 0) > 0.05)
        let noise = NoiseState(); noise.kind = .pink
        let pink = (0..<20000).map { _ in noise.next() }; noise.kind = .brown; let brown = (0..<20000).map { _ in noise.next() }
        check("ambient noise: pink and brown stay finite and bounded", (pink + brown).allSatisfy { $0.isFinite && abs($0) < 1.5 } && (brown.map { abs($0) }.max() ?? 0) > 0.01)
        check("idle collapse: only an open, unpinned panel past the limit", IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 31, limit: 30)
              && !IdleCollapse.shouldCollapse(expanded: true, pinned: true, idle: 31, limit: 30) && !IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 31, limit: 0)
              && !IdleCollapse.shouldCollapse(expanded: false, pinned: false, idle: 31, limit: 30) && !IdleCollapse.shouldCollapse(expanded: true, pinned: false, idle: 10, limit: 30))
    }
}
