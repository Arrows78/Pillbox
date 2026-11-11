import AppKit
import SwiftUI

/// Hosting view that lets clicks fall through everywhere outside the visible shape.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var activeRect: NSRect = .zero
    /// The panel never activates the app, so the very first click must reach the buttons.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return activeRect.contains(local) ? super.hitTest(point) : nil
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private let hosting: PassthroughHostingView<NotchRootView>
    private let model = NotchModel.shared
    /// Kept for the whole run: the controller is created once by AppDelegate and never torn down, so the tokens are not removed.
    private var observers: [NSObjectProtocol] = []
    /// The settings `applyCapturePreference` reads, as last applied; other defaults changes do not need a re-apply.
    private var capturePrefs = ""

    init() {
        let size = NotchModel.windowSize
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        hosting = PassthroughHostingView(rootView: NotchRootView())
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        reposition()
        applyCapturePreference()
        capturePrefs = Self.capturePreferenceSignature()
        panel.orderFrontRegardless()
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let signature = Self.capturePreferenceSignature()
                guard signature != self.capturePrefs else { return }
                self.capturePrefs = signature
                self.applyCapturePreference()
            }
        })

        observers.append(NotificationCenter.default.addObserver(forName: .notchStateChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateActiveRect() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let detected = NotchGeometry.detect()
                self?.model.geometry = detected
                self?.reposition()
                self?.applyCapturePreference(detected: detected)
            }
        })
    }

    /// The defaults that decide how the island is shown: capture, full screen, mirroring, the hidden notch, the screen and the pill width.
    private static func capturePreferenceSignature() -> String {
        let d = UserDefaults.standard
        return ["hideFromCapture", "hideEverywhere", "hideInFullScreen", "hideNotch", "hideWhileMirroring", "targetDisplay", "pillWidth"]
            .map { "\(d.object(forKey: $0) ?? "")" }.joined(separator: "|")
    }

    /// Visible shape rect in screen coordinates (used for hover tests).
    var shapeRectOnScreen: NSRect {
        let f = panel.frame
        let s = model.size(hasWings: LiveState.shared.hasWings)
        return NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    func reposition() {
        guard let screen = model.geometry.screen ?? NSScreen.main else { return }
        let size = NotchModel.windowSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        updateActiveRect()
    }

    func updateActiveRect() {
        let s = model.size(hasWings: LiveState.shared.hasWings)
        let b = hosting.bounds
        // NSHostingView is flipped (origin top-left); plain NSViews are not.
        let y = hosting.isFlipped ? b.minY : b.maxY - s.height
        hosting.activeRect = NSRect(x: b.midX - s.width / 2, y: y, width: s.width, height: s.height)
        updateMouseRouting(at: NSEvent.mouseLocation)
    }

    /// The panel is larger than the shape, and a view that returns no hit still swallows the click there.
    /// So the window only takes the mouse while the pointer is over the visible shape; elsewhere clicks reach the windows below.
    func updateMouseRouting(at point: NSPoint, hidden: Bool = UserDefaults.standard.bool(forKey: "hideEverywhere")) {
        panel.ignoresMouseEvents = hidden || !shapeRectOnScreen.insetBy(dx: -4, dy: -4).contains(point)
    }

    /// Asks capture apps to leave the island out of screenshots, recordings and screen shares.
    /// `known`: the geometry the caller has just detected, so it is not detected twice.
    func applyCapturePreference(detected known: NotchGeometry? = nil) {
        panel.sharingType = UserDefaults.standard.bool(forKey: "hideFromCapture") ? .none : .readOnly
        // Hidden everywhere: the island is transparent and lets clicks through, but its shortcuts keep working.
        let hidden = UserDefaults.standard.bool(forKey: "hideEverywhere")
        panel.alphaValue = hidden ? 0 : 1
        updateMouseRouting(at: NSEvent.mouseLocation, hidden: hidden)
        panel.collectionBehavior = UserDefaults.standard.bool(forKey: "hideInFullScreen") ? [.canJoinAllSpaces, .stationary, .ignoresCycle] : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let detected = known ?? NotchGeometry.detect()
        // The pill width setting changes the geometry without changing the screen.
        let g = model.geometry
        if detected.screen != g.screen || detected.width != g.width || detected.height != g.height { model.geometry = detected; reposition() }
        NotchHider.shared.apply(screen: model.geometry.screen ?? NSScreen.main, height: model.geometry.height)
        // A mirrored display copies the whole screen, so capture exclusion cannot hide the island on a projector: it goes away outright.
        if Mirroring.shouldHide { panel.orderOut(nil) } else if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
