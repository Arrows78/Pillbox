import Foundation
import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

enum OCR {
    /// The text in the image, or nil when Vision could not read it, so a failure is not taken for an empty screen.
    static func recognize(in image: CGImage) -> String? {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image).perform([req]) } catch { return nil }
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

enum ScreenGrab {
    enum Failure: Error { case noDisplay }

    /// Captures a rectangle given in AppKit screen coordinates (needs Screen Recording).
    static func capture(_ rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure.noDisplay }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = sourceRect(for: rect, on: screen.frame)
        cfg.width = max(Int(rect.width * screen.backingScaleFactor), 1); cfg.height = max(Int(rect.height * screen.backingScaleFactor), 1)
        cfg.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
    }

    /// AppKit rect (bottom-left origin, global) to a display-local rect with a top-left origin.
    nonisolated static func sourceRect(for rect: CGRect, on screen: CGRect) -> CGRect {
        CGRect(x: rect.minX - screen.minX, y: screen.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: Region picker

/// Watches a part of the screen and tells you when its text changes (a percentage, a status, a price).
@MainActor
final class WindowWatch: ObservableObject {
    static let shared = WindowWatch()
    @Published private(set) var region: CGRect?
    @Published private(set) var lastText = ""
    private var timer: Timer?
    private var busy = false
    private var reading: Task<Void, Never>?

    var watching: Bool { region != nil }

    nonisolated static func normalize(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    nonisolated static func changed(_ old: String, _ new: String) -> Bool { normalize(old) != normalize(new) }

    func choose() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { PermissionsCenter.shared.openSettings(.screenRecording); return }
        RegionPicker.shared.pick { [weak self] r in
            guard let self, let r else { return }
            self.region = r; self.lastText = ""
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { self.check() } }
            self.check()
            NotchModel.shared.show(Activity(symbol: "eye.fill", title: localized("Watching this area"), tint: .blue))
        }
    }

    func stop() { timer?.invalidate(); reading?.cancel(); region = nil; lastText = "" }

    private func check() {
        guard let r = region, !busy else { return }
        busy = true
        reading = Task {
            defer { busy = false }
            guard let img = try? await ScreenGrab.capture(r), !Task.isCancelled else { return }
            // A failed read is skipped rather than stored as "": the next real reading must still count as a change.
            guard let text = await Task.detached(operation: { OCR.recognize(in: img) }).value, !Task.isCancelled else { return }
            let old = lastText
            lastText = text
            if !old.isEmpty, Self.changed(old, text) {
                NotchModel.shared.show(Activity(symbol: "eye.fill", title: localized("Watched area changed"), subtitle: Self.normalize(text).prefix(80).description, tint: .blue, duration: 6))
            }
        }
    }
}

// MARK: Keychain + Ask about screen
