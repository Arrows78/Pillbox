import AppKit
import Combine

// MARK: Extra brightness on XDR and HDR displays

/// Lifts XDR and HDR screens above standard white with an almost transparent, extended-range window over each of
/// them. The window ignores the mouse and follows screen changes; switching the option off removes it.
@MainActor
final class ExtraBrightness {
    static let shared = ExtraBrightness()
    nonisolated static let key = "extraBrightness"
    private var windows: [NSWindow] = []
    private var started = false
    private var batteryWatch: AnyCancellable?

    /// Off on its own in Low Power Mode, on a low battery, or when the Mac runs hot: the boost costs power and heat.
    static func allowed(lowPower: Bool, batteryLevel: Int, pluggedIn: Bool, thermal: ProcessInfo.ThermalState) -> Bool {
        !lowPower && (pluggedIn || batteryLevel > 20) && thermal.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    /// Screens whose hardware can show content above SDR white.
    static var capableScreens: [NSScreen] { NSScreen.screens.filter { $0.maximumExtendedDynamicRangeColorComponentValue > 1 } }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ExtraBrightness.shared.apply() }
        }
        for name in [NSNotification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ExtraBrightness.shared.apply() }
            }
        }
        batteryWatch = BatteryService.shared.objectWillChange.receive(on: DispatchQueue.main).sink { _ in
            MainActor.assumeIsolated { ExtraBrightness.shared.apply() }
        }
        apply()
    }

    func apply() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        guard UserDefaults.standard.bool(forKey: Self.key) else { return }
        let battery = BatteryService.shared
        guard Self.allowed(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, batteryLevel: battery.level, pluggedIn: battery.pluggedIn,
                           thermal: ProcessInfo.processInfo.thermalState) else { return }
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
