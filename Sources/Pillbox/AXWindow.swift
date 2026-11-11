import AppKit
import ApplicationServices

/// Window geometry through the Accessibility API. AX measures y from the top edge of the primary screen, AppKit from its bottom edge.
@MainActor
enum AXWindow {
    /// The window's origin and size, or nil when either attribute cannot be read.
    static func frame(of window: AXUIElement) -> (origin: CGPoint, size: CGSize)? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success, let pv = posRef,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success, let sv = sizeRef,
              AXValueGetValue(pv as! AXValue, .cgPoint, &pos), AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return nil }
        return (pos, size)
    }

    /// Accessibility calls run on the main thread, so a hung app must not hold it for long: each call waits at most a second.
    static let messagingTimeout: Float = 1

    /// The window under an AppKit point, or nil when there is none.
    static func window(at point: CGPoint) -> AXUIElement? {
        let ax = flipped(point)
        var element: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        guard AXUIElementCopyElementAtPosition(system, Float(ax.x), Float(ax.y), &element) == .success,
              let under = element else { return nil }
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(under, kAXWindowAttribute as CFString, &winRef) == .success, let w = winRef else { return nil }
        return (w as! AXUIElement)
    }

    /// Converts a point between AppKit and AX. The two differ only in where y starts, so the same flip works both ways.
    static func flipped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Converts a rect between AppKit and AX, the same way as `flipped(_:CGPoint)`.
    static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
}
