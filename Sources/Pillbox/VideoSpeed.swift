import AppKit

// MARK: Playback speed for video in browsers

/// Sets the playback rate of every video in the front browser tab through the browser's own JavaScript bridge.
/// The browser must allow it: "Allow JavaScript from Apple Events" (Safari: Develop menu; Chromium browsers: View > Developer).
@MainActor
enum VideoSpeed {
    /// Bundle identifier to the name AppleScript knows the browser by.
    static let browsers: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave Browser",
        "company.thebrowser.Browser": "Arc",
        "org.chromium.Chromium": "Chromium",
    ]

    /// The AppleScript that sets `rate`, or nil when `bundleID` is not a known browser.
    nonisolated static func script(rate: Double, bundleID: String?) -> String? {
        guard let id = bundleID, let name = browsers[id] else { return nil }
        let js = "document.querySelectorAll('video').forEach(v => v.playbackRate = \(rate))"
        if id == "com.apple.Safari" {
            return "tell application \"Safari\" to do JavaScript \"\(js)\" in front document"
        }
        return "tell application \"\(name)\" to tell active tab of front window to execute javascript \"\(js)\""
    }

    static func set(_ rate: Double) {
        let app = NSWorkspace.shared.frontmostApplication
        guard let source = script(rate: rate, bundleID: app?.bundleIdentifier) else {
            NotchModel.shared.show(Activity(symbol: "speedometer", title: L("Open a browser with a video"), duration: 2))
            return
        }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        let label = rate == 1 ? "1×" : String(format: "%g×", rate)
        if error == nil {
            NotchModel.shared.show(Activity(symbol: "speedometer", title: L("Video speed %@", label), tint: .white, duration: 1.6))
        } else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: L("Allow JavaScript from Apple Events in the browser"), tint: .orange, duration: 4))
        }
    }
}
