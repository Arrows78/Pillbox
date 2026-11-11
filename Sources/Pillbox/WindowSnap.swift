import AppKit
import ApplicationServices

enum SnapZone: String, CaseIterable {
    case left = "Left half", right = "Right half", top = "Top half", bottom = "Bottom half"
    case full = "Full screen", center = "Center", leftThird = "Left third", rightThird = "Right third"

    func frame(in r: CGRect) -> CGRect {
        let w = r.width, h = r.height
        switch self {
        case .left: return CGRect(x: r.minX, y: r.minY, width: w / 2, height: h)
        case .right: return CGRect(x: r.minX + w / 2, y: r.minY, width: w / 2, height: h)
        case .top: return CGRect(x: r.minX, y: r.minY, width: w, height: h / 2)
        case .bottom: return CGRect(x: r.minX, y: r.minY + h / 2, width: w, height: h / 2)
        case .full: return r
        case .center: return CGRect(x: r.minX + w * 0.15, y: r.minY + h * 0.1, width: w * 0.7, height: h * 0.8)
        case .leftThird: return CGRect(x: r.minX, y: r.minY, width: w / 3, height: h)
        case .rightThird: return CGRect(x: r.minX + w * 2 / 3, y: r.minY, width: w / 3, height: h)
        }
    }
}

/// Moves the focused window of the front app with the Accessibility API.
@MainActor
enum WindowSnap {
    static func snap(_ zone: SnapZone) {
        guard AXIsProcessTrusted() else {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            return
        }
        // The palette is non-activating, so the front app is still the user's.
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success, let window = win else { return }
        let w = window as! AXUIElement

        // Without a readable frame there is no screen to measure from, so the window is left where it is.
        guard let frame = AXWindow.frame(of: w) else { return }
        // The centre decides which screen the window is on; AX and AppKit differ only in where y starts.
        let center = AXWindow.flipped(CGPoint(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2))
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        let visibleFrameTopLeft = AXWindow.flipped(vis)
        let target = zone.frame(in: visibleFrameTopLeft)
        // Setting size, position, then size again is what makes apps with minimum sizes land correctly.
        func apply(_ f: CGRect) {
            var p = f.origin, s = f.size
            if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
            if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
            if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        }
        apply(target)
    }
}
