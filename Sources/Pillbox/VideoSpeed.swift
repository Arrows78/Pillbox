import AppKit

// MARK: Playback speed for video in browsers

/// Sets the playback rate of every video in the front browser tab through the browser's own JavaScript bridge.
/// The browser must allow it: "Allow JavaScript from Apple Events" (Safari: Develop menu; Chromium browsers: View > Developer).
@MainActor
enum VideoSpeed {
    /// Bundle identifier to the name AppleScript knows the browser by.
    nonisolated static let browsers: [String: String] = [
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

    /// Why AppleScript could not set the speed, told apart by Apple's error number and the browser's message.
    enum Failure: Equatable {
        case automationDenied, notRunning, javaScriptOff, other

        /// `number` is the AppleScript error number: -1743 when Automation is refused, -600 when the browser is not running.
        nonisolated static func classify(number: Int?, message: String?) -> Failure {
            switch number {
            case -1743: return .automationDenied
            case -600: return .notRunning
            default: break
            }
            if message?.localizedCaseInsensitiveContains("JavaScript") == true { return .javaScriptOff }
            return .other
        }

        var text: String {
            switch self {
            case .automationDenied: localized("Allow Pillbox to control the browser in Privacy & Security > Automation")
            case .notRunning: localized("The browser is not running")
            case .javaScriptOff: localized("Allow JavaScript from Apple Events in the browser")
            case .other: localized("Could not change the video speed")
            }
        }
    }

    static func set(_ rate: Double) {
        let app = NSWorkspace.shared.frontmostApplication
        guard let source = script(rate: rate, bundleID: app?.bundleIdentifier) else {
            NotchModel.shared.show(Activity(symbol: "speedometer", title: localized("Open a browser with a video"), duration: 2))
            return
        }
        let label = rate == 1 ? "1×" : String(format: "%g×", rate)
        // A browser that does not answer would freeze the UI here, so the script runs in the background and reports back.
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let failure = error.map { Failure.classify(number: $0[NSAppleScript.errorNumber] as? Int, message: $0[NSAppleScript.errorMessage] as? String) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let failure {
                        NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: failure.text, tint: .orange, duration: 4))
                    } else {
                        NotchModel.shared.show(Activity(symbol: "speedometer", title: localized("Video speed %@", label), tint: .white, duration: 1.6))
                    }
                }
            }
        }
    }
}
