import SwiftUI
import Foundation
import AppKit

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
                     "Local API: \(Preferences.devAPI.value ? "on" : "off")"]
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
