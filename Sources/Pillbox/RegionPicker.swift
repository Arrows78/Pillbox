import Foundation
import AppKit
import ScreenCaptureKit
import SwiftUI
import Vision

private final class PickerWindow: NSWindow { override var canBecomeKey: Bool { true } }

private final class PickerView: NSView {
    var start: NSPoint?, current: NSPoint?
    var onDone: ((NSRect?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private var rect: NSRect? { start.flatMap { s in current.map { NSRect(x: min(s.x, $0.x), y: min(s.y, $0.y), width: abs(s.x - $0.x), height: abs(s.y - $0.y)) } } }
    override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); current = start; needsDisplay = true }
    override func mouseDragged(with e: NSEvent) { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with e: NSEvent) {
        guard let r = rect, r.width > 8, r.height > 8, let w = window else { onDone?(nil); return }
        onDone?(w.convertToScreen(r))
    }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { onDone?(nil) } }
    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill()
        guard let r = rect else { return }
        NSColor.clear.setFill(); r.fill(using: .copy)
        NSColor.white.setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 1.5; p.stroke()
    }
}

@MainActor
final class RegionPicker {
    static let shared = RegionPicker()
    private var windows: [NSWindow] = []

    func pick(_ done: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        NotchModel.shared.collapse()
        func finish(_ r: NSRect?) { windows.forEach { $0.orderOut(nil) }; windows = []; done(r) }
        for s in NSScreen.screens {
            let w = PickerWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .clear; w.isOpaque = false; w.level = .screenSaver; w.isReleasedWhenClosed = false
            let v = PickerView(frame: NSRect(origin: .zero, size: s.frame.size)); v.onDone = { finish($0) }
            w.contentView = v; w.makeKeyAndOrderFront(nil); w.makeFirstResponder(v)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: Window watch
