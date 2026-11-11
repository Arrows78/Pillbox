import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func shelf() {
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

    static func watchers() {
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

    static func converter() {
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
        case .failure(let e):
            // A gradient has no subject, so the only acceptable failure is that specific message.
            check("convert: cut-out returns a PNG, or a clean error without a subject", { () -> Bool in guard case .failed(let m)? = e as? ConvertError else { return false }; return m == localized("No subject found") }(), "\(e)")
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

    static func downloadsAndBuild() {
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
    }

    static func quickCapture() {
        check("capture: keyword and argument", QuickCapture.argument("event lunch with Sam tomorrow noon", keywords: ["event", "ev"]) == "lunch with Sam tomorrow noon"
              && QuickCapture.argument("ev  x", keywords: ["event", "ev"]) == "x" && QuickCapture.argument("events", keywords: ["event"]) == nil && QuickCapture.argument("event ", keywords: ["event"]) == nil)
        check("capture: AppleScript text is escaped", QuickCapture.appleScriptString("say \"hi\" \\ now") == "\"say \\\"hi\\\" \\\\ now\"" && QuickCapture.appleScriptString("a\nb") == "\"a\" & linefeed & \"b\"", QuickCapture.appleScriptString("say \"hi\" \\ now"))
        // The escaped expression must be valid AppleScript: evaluating it returns the original text.
        let nasty = "quote \" slash \\ end"
        let back = MusicService.run("return \(QuickCapture.appleScriptString(nasty))")?.stringValue
        check("capture: escaped text survives a round trip through AppleScript", back == nasty, back ?? "nil")
    }

    static func recordingQRAnnotate() {
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

    static func annotateSteps() {
        if let blank = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() {
            let color = Annotator.colors[0].cgColor
            let out = Annotator.render(blank, marks: [Mark(kind: .step, color: color, points: [CGPoint(x: 20, y: 20)]),
                                                      Mark(kind: .step, color: color, points: [CGPoint(x: 40, y: 20)]),
                                                      Mark(kind: .loupe, color: color, points: [CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 80)])], pixelated: nil)
            check("annotate: numbered steps and a loupe render onto the picture at its size", out?.width == 100 && out?.height == 100)
        }
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
