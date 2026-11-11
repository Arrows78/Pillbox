import AppKit
import ApplicationServices

// MARK: Move and resize windows with the mouse

/// Holding ⌃⌥ and dragging moves the window under the pointer; adding ⇧ resizes it from its bottom-right corner.
/// Needs Accessibility, like window snapping. The monitors only observe: the click still reaches the app.
@MainActor
final class WindowDrag {
    static let shared = WindowDrag()
    nonisolated static let key = "windowDrag"
    static let minSize = CGSize(width: 200, height: 120)

    private var monitors: [Any] = []
    private struct Grab { let window: AXUIElement; let origin: CGPoint; let size: CGSize; let mouse: NSPoint; let resize: Bool }
    private var grab: Grab?

    /// The origin or size after the pointer moved by (dx, dy) in AppKit terms; sizes never drop below `minSize`.
    nonisolated static func moved(_ origin: CGPoint, by dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + dx, y: origin.y - dy)   // Accessibility origins are top-left, AppKit's bottom-left
    }

    nonisolated static func resized(_ size: CGSize, by dx: CGFloat, _ dy: CGFloat) -> CGSize {
        CGSize(width: max(minSize.width, size.width + dx), height: max(minSize.height, size.height + dy))
    }

    /// Starts or stops the monitors to match the switch. Safe to call again.
    func apply() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        grab = nil
        guard UserDefaults.standard.bool(forKey: Self.key) else { return }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { e in MainActor.assumeIsolated { WindowDrag.shared.begin(e) } },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in MainActor.assumeIsolated { WindowDrag.shared.drag() } },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in MainActor.assumeIsolated { WindowDrag.shared.grab = nil } },
        ].compactMap { $0 }
    }

    private func begin(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains([.control, .option]), AXIsProcessTrusted() else { return }
        let p = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(primaryH - p.y), &element) == .success,
              let under = element else { return }
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(under, kAXWindowAttribute as CFString, &winRef) == .success, let w = winRef else { return }
        let window = w as! AXUIElement
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success, let pv = posRef,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success, let sv = sizeRef else { return }
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        grab = Grab(window: window, origin: pos, size: size, mouse: p, resize: mods.contains(.shift))
    }

    private func drag() {
        guard let g = grab else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - g.mouse.x, dy = p.y - g.mouse.y
        if g.resize {
            var s = Self.resized(g.size, by: dx, -dy)
            if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(g.window, kAXSizeAttribute as CFString, v) }
        } else {
            var o = Self.moved(g.origin, by: dx, dy)
            if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(g.window, kAXPositionAttribute as CFString, v) }
        }
    }
}
