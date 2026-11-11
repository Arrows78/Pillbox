import AppKit

// MARK: Extra brightness on XDR and HDR displays

/// Lifts XDR and HDR screens above standard white with an almost transparent, extended-range window over each of
/// them. The window ignores the mouse and follows screen changes; switching the option off removes it.
@MainActor
final class ExtraBrightness {
    static let shared = ExtraBrightness()
    nonisolated static let key = "extraBrightness"
    private var windows: [NSWindow] = []
    private var started = false

    /// Screens whose hardware can show content above SDR white.
    static var capableScreens: [NSScreen] { NSScreen.screens.filter { $0.maximumExtendedDynamicRangeColorComponentValue > 1 } }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ExtraBrightness.shared.apply() }
        }
        apply()
    }

    func apply() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard UserDefaults.standard.bool(forKey: Self.key) else { return }
        for screen in Self.capableScreens {
            let headroom = screen.maximumExtendedDynamicRangeColorComponentValue
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.wantsExtendedDynamicRangeContent = true
            // Extended-range white at the screen's headroom, at a few percent opacity: barely visible, but above SDR white.
            if let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3),
               let color = CGColor(colorSpace: space, components: [headroom, headroom, headroom, 0.04]) {
                view.layer?.backgroundColor = color
            }
            w.contentView = view
            w.orderFrontRegardless()
            windows.append(w)
        }
    }
}
