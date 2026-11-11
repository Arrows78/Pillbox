import AppKit

/// Music or a video playing in a browser tab, read through the browser's own JavaScript bridge (the same bridge the
/// video speed control uses). Only browsers that allow JavaScript from Apple Events can be read; Firefox has no such
/// bridge and is not supported.
enum BrowserMusic {
    /// What the front tab's first media element reports.
    struct Now: Equatable {
        let bundleID: String
        let browser: String
        let title: String
        let playing: Bool
        let position: Double
        let duration: Double
    }

    /// The JavaScript that finds the first audio or video element of the page. It answers `none` when there is none.
    static let readJS = "(function(){var m=document.querySelector('video,audio');if(!m){return 'none'};return [document.title,m.paused?'1':'0',m.currentTime,m.duration].join('|')})()"
    static let toggleJS = "(function(){var m=document.querySelector('video,audio');if(m){m.paused?m.play():m.pause()}})()"

    /// The AppleScript that runs `js` in the front tab of a browser, or nil for a browser that cannot be scripted that way.
    nonisolated static func script(bundleID: String, js: String) -> String? {
        guard let name = VideoSpeed.browsers[bundleID] else { return nil }
        if bundleID == "com.apple.Safari" {
            return "tell application \"Safari\" to do JavaScript \"\(js)\" in front document"
        }
        return "tell application \"\(name)\" to tell active tab of front window to execute javascript \"\(js)\""
    }

    /// Reads `title|paused|position|duration`. The title may hold a `|`, so the three numbers are taken from the end.
    nonisolated static func parse(_ output: String, bundleID: String, browser: String) -> Now? {
        guard output != "none", output != "" else { return nil }
        let fields = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4 else { return nil }
        let count = fields.count
        let position = Double(fields[count - 2].replacingOccurrences(of: ",", with: ".")) ?? 0
        let duration = Double(fields[count - 1].replacingOccurrences(of: ",", with: ".")) ?? 0
        return Now(bundleID: bundleID, browser: browser, title: fields[0..<(count - 3)].joined(separator: "|"),
                   playing: fields[count - 3] == "0", position: position, duration: duration.isFinite ? duration : 0)
    }

    /// The first running browser that has media playing in its front tab.
    nonisolated static func read() -> Now? {
        for (bundleID, name) in VideoSpeed.browsers.sorted(by: { $0.key < $1.key }) where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let source = script(bundleID: bundleID, js: readJS),
                  let output = MusicService.run(source)?.stringValue,
                  let now = parse(output, bundleID: bundleID, browser: name) else { continue }
            return now
        }
        return nil
    }

    nonisolated static func togglePlayback(bundleID: String) {
        guard let source = script(bundleID: bundleID, js: toggleJS) else { return }
        _ = MusicService.run(source)
    }
}
