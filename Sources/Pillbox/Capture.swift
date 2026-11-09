import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import Vision

// MARK: Screen recording

/// Writes the frames of an SCStream to a .mov (H.264, video only). Samples arrive on `queue`.
final class RecordingSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "pillbox.recording")
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    var onStop: (@Sendable (Error) -> Void)?

    init(url: URL, width: Int, height: Int) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, Self.isComplete(sb) else { return }
        if !started { writer.startSession(atSourceTime: sb.presentationTimeStamp); started = true }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop?(error) }

    /// Idle and blank frames carry no picture: only complete ones are written.
    private static func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = att.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    /// True when at least one frame was written and the file was closed cleanly.
    func finish() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard self.started else { self.writer.cancelWriting(); c.resume(returning: false); return }
                self.input.markAsFinished()
                self.writer.finishWriting { c.resume(returning: self.writer.status == .completed) }
            }
        }
    }
}

@MainActor
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()
    @Published var since: Date?   // settable for --render only; start() and stop() own it
    private var stream: SCStream?
    private var sink: RecordingSink?
    private var starting = false

    var recording: Bool { since != nil }

    /// H.264 tops out at 4096×2304: larger captures are scaled down, keeping the aspect ratio, to even sizes.
    nonisolated static func outputSize(width: CGFloat, height: CGFloat) -> (width: Int, height: Int) {
        let k = min(1, 4096 / max(width, 1), 2304 / max(height, 1))
        func even(_ v: CGFloat) -> Int { max(2, Int(v * k) / 2 * 2) }
        return (even(width), even(height))
    }

    nonisolated static func fileName(at date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Pillbox Recording \(f.string(from: date)).mov"
    }

    func toggle() { recording ? stop() : start(area: nil) }

    func recordArea() {
        guard !recording, allowed() else { return }
        RegionPicker.shared.pick { [weak self] r in if let r { self?.start(area: r) } }
    }

    private func allowed() -> Bool {
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() { return true }
        PermissionsCenter.shared.openSettings(.screenRecording); return false
    }

    /// Records the display under the pointer, or `area` (AppKit screen coordinates). Pillbox's own windows are left out.
    func start(area: CGRect?) {
        guard !recording, !starting, allowed() else { return }
        starting = true
        NotchModel.shared.collapse()
        Task {
            defer { starting = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mouse = NSEvent.mouseLocation
                guard let screen = area.flatMap({ a in NSScreen.screens.first { $0.frame.intersects(a) } }) ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
                      let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else { throw ScreenGrab.Failure.noDisplay }
                let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
                let rect = area.map { $0.intersection(screen.frame) } ?? screen.frame
                let size = Self.outputSize(width: rect.width * screen.backingScaleFactor, height: rect.height * screen.backingScaleFactor)
                let cfg = SCStreamConfiguration()
                if area != nil { cfg.sourceRect = ScreenGrab.sourceRect(for: rect, on: screen.frame) }
                cfg.width = size.width; cfg.height = size.height
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                cfg.showsCursor = true; cfg.queueDepth = 6
                let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
                let sink = try RecordingSink(url: ShelfService.uniqueURL(desktop.appendingPathComponent(Self.fileName(at: Date()))), width: size.width, height: size.height)
                sink.onStop = { _ in DispatchQueue.main.async { MainActor.assumeIsolated { ScreenRecorder.shared.stop(failed: true) } } }
                let s = SCStream(filter: filter, configuration: cfg, delegate: sink)
                try s.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
                try await s.startCapture()
                stream = s; self.sink = sink; since = Date()
                NotificationCenter.default.post(name: .notchStateChanged, object: nil)
            } catch {
                NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Could not start recording", subtitle: error.localizedDescription, tint: .orange, duration: 5))
            }
        }
    }

    func stop(failed: Bool = false) {
        guard let s = stream, let sink else { return }
        stream = nil; self.sink = nil; since = nil
        NotificationCenter.default.post(name: .notchStateChanged, object: nil)
        Task {
            if !failed { try? await s.stopCapture() }
            let ok = await sink.finish()
            if ok {
                ShelfService.shared.add([sink.url])
                NotchModel.shared.show(Activity(symbol: "record.circle", title: "Recording saved", subtitle: sink.url.lastPathComponent, tint: .red,
                                                actionTitle: "Reveal", action: { NSWorkspace.shared.activateFileViewerSelecting([sink.url]) }, duration: 6))
            } else {
                try? FileManager.default.removeItem(at: sink.url)
                NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Recording failed", tint: .orange))
            }
        }
    }
}

/// Red dot and elapsed time, for the collapsed pill and the open panel's header.
struct RecordingDot: View {
    var body: some View { Circle().fill(.red).frame(width: 9, height: 9).shadow(color: .red.opacity(0.7), radius: 3) }
}

struct RecordingStopButton: View {
    @ObservedObject var rec = ScreenRecorder.shared
    var body: some View {
        if let s = rec.since {
            Button { rec.stop() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill").font(.system(size: 8))
                    Text(s, style: .timer).font(.system(size: 10, weight: .semibold, design: .monospaced)).lineLimit(1)
                }.foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3).background(.red, in: Capsule()).fixedSize()
            }.buttonStyle(.plain).hoverTip(L("Stop recording")).accessibilityLabel("Stop recording")
        }
    }
}

// MARK: QR codes

enum QRReader {
    /// Payloads of the QR codes and barcodes in the picture, without duplicates, in reading order.
    nonisolated static func decode(_ image: CGImage) -> [String] {
        let req = VNDetectBarcodesRequest()
        try? VNImageRequestHandler(cgImage: image).perform([req])
        let found = (req.results ?? []).sorted { ($0.boundingBox.maxY, -$0.boundingBox.minX) > ($1.boundingBox.maxY, -$1.boundingBox.minX) }
        var out: [String] = []
        for o in found { if let p = o.payloadStringValue, !p.isEmpty, !out.contains(p) { out.append(p) } }
        return out
    }

    /// Only web links get an Open button; anything else (Wi-Fi, text, tel:, javascript:) is copied.
    nonisolated static func webLink(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host?.isEmpty == false else { return nil }
        return u
    }

    @MainActor static func scanScreen() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { PermissionsCenter.shared.openSettings(.screenRecording); return }
        NotchModel.shared.collapse()
        Task {
            var codes: [String] = []
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                for d in content.displays {
                    let cfg = SCStreamConfiguration()
                    let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == d.displayID }?.backingScaleFactor ?? 2
                    cfg.width = Int(CGFloat(d.width) * scale); cfg.height = Int(CGFloat(d.height) * scale); cfg.showsCursor = false
                    let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, excludingApplications: mine, exceptingWindows: []), configuration: cfg)
                    codes += await Task.detached { decode(img) }.value.filter { !codes.contains($0) }
                }
            } catch {
                NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: "Could not capture the screen", tint: .orange)); return
            }
            guard let code = codes.first else {
                NotchModel.shared.show(Activity(symbol: "qrcode.viewfinder", title: "No QR code on screen", tint: .orange)); return
            }
            let more = codes.count > 1 ? " (+\(codes.count - 1))" : ""
            if let u = webLink(code) {
                NotchModel.shared.show(Activity(symbol: "qrcode", title: "QR code link", subtitle: code + more, tint: .green, actionTitle: "Open link", action: { NSWorkspace.shared.open(u) }, duration: 10))
            } else {
                NotchModel.shared.show(Activity(symbol: "qrcode", title: "QR code", subtitle: code + more, tint: .green, actionTitle: "Copy", action: {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                }, duration: 10))
            }
        }
    }
}
