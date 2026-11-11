import AppKit
import SwiftUI

private func cleaningTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { CleaningLock.shared.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53, event.flags.contains(.maskCommand) {
        DispatchQueue.main.async { MainActor.assumeIsolated { CleaningLock.shared.stop() } }
    }
    return nil   // swallow every key, including media keys
}

/// Locks the keyboard while you wipe it (⌘⎋ unlocks), or blacks out the displays to clean the screen.
@MainActor
final class CleaningLock: ObservableObject {
    static let shared = CleaningLock()
    @Published private(set) var active = false
    @Published private(set) var remaining = 0
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var blackouts: [NSWindow] = []
    private var keyMonitors: [Any] = []

    func startKeyboardLock(seconds: Int = 60) {
        guard !active else { return }
        guard AXIsProcessTrusted() else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            NotchModel.shared.show(Activity(symbol: "lock.open", title: L("Accessibility needed"), subtitle: L("Allow Pillbox, then try again"), tint: .orange)); return
        }
        let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(0) { $0 | (1 << $1.rawValue) } | (1 << 14)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: cleaningTap, userInfo: nil) else {
            NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: L("Could not lock the keyboard"), subtitle: L("Allow Pillbox in Privacy & Security › Accessibility"), tint: .orange))
            return
        }
        tap = t; source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        begin(seconds)
    }

    /// macOS turns the tap off after a timeout or user input; it is switched back on so the lock keeps holding.
    func reenableTap() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    func startScreenBlackout(seconds: Int = 60) {
        guard !active else { return }
        for s in NSScreen.screens {
            let w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black; w.level = .screenSaver; w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.orderFrontRegardless(); blackouts.append(w)
        }
        NSCursor.hide()
        // A local monitor only sees events while Pillbox is active, and the blackout window cannot become key,
        // so a global monitor is needed too: the key or click that ends the blackout may go to another app.
        let dismiss: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown]
        keyMonitors = [
            NSEvent.addLocalMonitorForEvents(matching: dismiss) { [weak self] e in
                self?.stop(); return nil
            } as Any,
            NSEvent.addGlobalMonitorForEvents(matching: dismiss) { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { CleaningLock.shared.stop() } }
            } as Any
        ]
        begin(seconds)
    }

    private func begin(_ seconds: Int) {
        active = true; remaining = seconds
        NotchModel.shared.collapse()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 { self.stop() }
            }
        }
    }

    func stop() {
        guard active else { return }
        timer?.invalidate(); active = false
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
        if !blackouts.isEmpty { blackouts.forEach { $0.orderOut(nil) }; blackouts = []; NSCursor.unhide() }
        keyMonitors.forEach { NSEvent.removeMonitor($0) }; keyMonitors = []
        NotchModel.shared.show(Activity(symbol: "sparkles", title: L("All clean"), tint: .green, duration: 2))
    }
}
