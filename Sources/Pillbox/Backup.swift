import AppKit

/// Export, import and reset of the preferences. Only the keys listed here are ever read or written, and an imported
/// value must have the right type and range, so a hand-edited or foreign file can do no harm.
/// Left out on purpose: the local API switch and token, the Anthropic key (Keychain), and the data kept in
/// Application Support (clipboard history, notes, shelf, quick actions, which can hold shell commands).
enum SettingsBackup {
    enum Kind {
        case bool
        case number(ClosedRange<Double>)
        case text([String]?)   // nil accepts any text, a list restricts the value to it
        case texts
    }

    static var keys: [String: Kind] {
        var k: [String: Kind] = [:]
        for key in ["hoverOpen", "capsHUD", "downloadAlerts", "privacyIndicator", "volumeHUD", "keystrokeHUD", "hideFromCapture", "hideNotch",
                    "hyperKey", "hyperEscape", "hideMenuBarIcons", "menuBarCalendar", "liveSpectrum", "doubleTapOpen", "snapZones", "peekOnHover",
                    "desktopWidgets", "brightnessHUD", "focusIsland", "callIsland", "copyStack", "notificationIsland", "shakeToOpen", "buildIsland",
                    "hideInFullScreen", "screenshotShelf", "driveEject", "shortcutsOnly", "showMenuBarIcon"] { k[key] = .bool }
        for key in ["focusBlocking", "spaceIsland", "cameraGuard"] { k[key] = .bool }
        k["hoverDelay"] = .number(0.05...0.6)
        k["panelScale"] = .number(0.8...1.3)
        k["pillWidth"] = .number(120...260)
        k["fullChargeLevel"] = .number(80...100)
        k["usageAlert"] = .number(0...100)
        k["breakReminder"] = .number(0...240)
        k["playerSize"] = .number(160...400)
        k["lottieSpeed"] = .number(0.1...4)
        k["searchEngine"] = .text(WebSearch.engines.map(\.key))
        k["hudStyle"] = .text(["notch", "edge", "circle"])
        k["islandTheme"] = .text(IslandTheme.allCases.map(\.rawValue))
        k["doubleClickAction"] = .text(PillAction.allCases.map(\.rawValue))
        k["tripleClickAction"] = .text(PillAction.allCases.map(\.rawValue))
        k["mascot"] = .text(Mascot.allCases.map(\.rawValue))
        k["appearance"] = .text(["system", "light", "dark"])
        k["targetDisplay"] = .text(nil)
        k["lottiePath"] = .text(nil)
        k["pinnedStock"] = .text(nil)
        k["detachedTabs"] = .texts
        return k
    }

    private static let marker = "pillbox-settings"

    /// A value of the right type and range for `kind`, or nil.
    static func accepted(_ value: Any, _ kind: Kind) -> Any? {
        let isBool = CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
        switch kind {
        case .bool: return isBool ? value : nil
        case .number(let range):
            guard !isBool, let n = value as? NSNumber, n.doubleValue.isFinite else { return nil }
            let c = min(max(n.doubleValue, range.lowerBound), range.upperBound)
            return c == c.rounded() ? Int(c) as Any : c as Any
        case .text(let allowed):
            guard let s = value as? String, allowed?.contains(s) ?? true else { return nil }
            return s
        case .texts:
            guard let a = value as? [String] else { return nil }
            return a
        }
    }

    static func data(from store: UserDefaults = .standard) -> Data? {
        var settings: [String: Any] = [:]
        for key in keys.keys { if let v = store.object(forKey: key) { settings[key] = v } }
        let file: [String: Any] = ["format": marker, "version": 1, "settings": settings]
        return try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
    }

    /// Applies a backup; returns how many settings were restored, or nil when the file is not a Pillbox backup.
    @discardableResult
    static func restore(_ data: Data, into store: UserDefaults = .standard) -> Int? {
        guard let file = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              file["format"] as? String == marker, let settings = file["settings"] as? [String: Any] else { return nil }
        let known = keys
        var count = 0
        for (key, value) in settings {
            guard let kind = known[key], let ok = accepted(value, kind) else { continue }
            store.set(ok, forKey: key); count += 1
        }
        return count
    }

    /// Every setting back to its default (the code's defaults apply again once the stored value is gone).
    static func resetAll(in store: UserDefaults = .standard) {
        for key in keys.keys { store.removeObject(forKey: key) }
    }
}

/// What "Copy diagnostics" and "Report a problem" share: versions and permission states, no personal data.
enum Diagnostics {
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    static func name(_ s: PermissionState) -> String {
        switch s { case .granted: "granted"; case .denied: "denied"; case .notDetermined: "not asked"; case .unavailable: "unavailable" }
    }

    @MainActor static var text: String {
        #if arch(arm64)
        let arch = "Apple silicon"
        #else
        let arch = "Intel"
        #endif
        let notch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        var lines = ["Pillbox \(version)", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)",
                     "Displays: \(NSScreen.screens.count), notch: \(notch ? "yes" : "no")",
                     "Local API: \(UserDefaults.standard.bool(forKey: "devAPIEnabled") ? "on" : "off")"]
        for k in PermissionKind.allCases { lines.append("\(k.rawValue): \(name(PermissionsCenter.shared.state(of: k)))") }
        return lines.joined(separator: "\n")
    }
}

/// A prefilled GitHub issue. Nothing is sent until the user submits it in the browser.
enum ProblemReport {
    static let maxBodyLength = 3500

    static func url(diagnostics: String) -> URL? {
        var body = "**What happened?**\n\n\n**Diagnostics**\n```\n\(diagnostics)\n```\n"
        if body.count > maxBodyLength { body = String(body.prefix(maxBodyLength)) + "\n…```" }
        var c = URLComponents(string: "https://github.com/Arrows78/Pillbox/issues/new")
        c?.queryItems = [URLQueryItem(name: "title", value: "Problem: "), URLQueryItem(name: "body", value: body)]
        return c?.url
    }

    @MainActor static func open() {
        if let u = url(diagnostics: Diagnostics.text) { NSWorkspace.shared.open(u) }
    }
}

/// Asks GitHub for the latest release, only when the user chooses "Check for updates…". Nothing is downloaded or
/// installed: the user is offered the release page.
enum UpdateCheck {
    static let api = "https://api.github.com/repos/Arrows78/Pillbox/releases/latest"
    @MainActor private static var checking = false

    /// True when `latest` is a newer version than `current` ("v1.2.0" and "1.2" are accepted).
    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The release page, only when it is an https link on github.com.
    static func releasePage(from json: [String: Any]) -> URL? {
        guard let s = json["html_url"] as? String, let u = URL(string: s), u.scheme == "https", u.host == "github.com" else { return nil }
        return u
    }

    @MainActor
    static func run() {
        guard !checking, let url = URL(string: api) else { return }
        checking = true
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            let json = ok ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } : nil
            DispatchQueue.main.async { MainActor.assumeIsolated { checking = false; present(json) } }
        }.resume()
    }

    @MainActor
    private static func present(_ json: [String: Any]?) {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let alert = NSAlert()
        NSApp.activate(ignoringOtherApps: true)
        guard let json, let tag = json["tag_name"] as? String else {
            alert.messageText = L("Could not check for updates")
            alert.informativeText = L("Check your connection and try again.")
            alert.runModal(); return
        }
        guard isNewer(tag, than: current) else {
            alert.messageText = L("Pillbox %@ is up to date", current)
            alert.runModal(); return
        }
        alert.messageText = L("Pillbox %@ is available", tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")))
        alert.informativeText = L("You are using version %@.", current)
        alert.addButton(withTitle: L("View release"))
        alert.addButton(withTitle: L("Later"))
        if alert.runModal() == .alertFirstButtonReturn, let page = releasePage(from: json) { NSWorkspace.shared.open(page) }
    }
}
