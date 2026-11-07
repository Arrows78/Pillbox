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

        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        if AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success { AXValueGetValue(posRef as! AXValue, .cgPoint, &pos) }
        if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }

        // AX uses a top-left origin on the primary screen; AppKit is bottom-left.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let center = CGPoint(x: pos.x + size.width / 2, y: primaryH - (pos.y + size.height / 2))
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        let top = CGRect(x: vis.minX, y: primaryH - vis.maxY, width: vis.width, height: vis.height)
        let target = zone.frame(in: top)
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
