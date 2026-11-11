import AppKit
import SwiftUI

/// How the pointer and dragged items reach the island: hovering the notch opens it, leaving closes it, a file dragged toward
/// it opens the shelf, and a window dragged toward it shows the snap zones.
@MainActor
final class IslandInteraction {
    private let controller: NotchWindowController
    private var monitors: [Any] = []
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    /// True while a file drag has pinned the shelf open, so the mouse-up after any other click leaves the pin alone.
    private var shelfPinned = false
    private var dragPasteboardCount = 0
    private var shake = ShakeDetector()

    init(controller: NotchWindowController) { self.controller = controller }

    func start() {
        setupHover()
        setupDragToShelf()
    }


    private func setupHover() {
        let handler: (NSEvent?) -> Void = { [weak self] _ in self?.mouseMoved() }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { e in
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(e) } }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { e in handler(e); return e } as Any)
    }

    private func mouseMoved() {
        let model = NotchModel.shared
        let p = NSEvent.mouseLocation
        controller.updateMouseRouting(at: p)
        let rect = controller.shapeRectOnScreen
        if !model.expanded {
            leaveTask?.cancel()
            // The strip includes the screen edge so a flick to the top still counts.
            let hot = rect.insetBy(dx: -4, dy: 0).union(NSRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 3))
            if Preferences.hoverOpen.value, hot.contains(p) {
                guard hoverTask == nil else { return }
                let delay = Preferences.hoverDelay.value.nonZero ?? Preferences.hoverDelay.defaultValue
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    defer { self?.hoverTask = nil }
                    guard !Task.isCancelled, let self, self.controller.shapeRectOnScreen.insetBy(dx: -4, dy: 0).contains(NSEvent.mouseLocation) || NSEvent.mouseLocation.y >= rect.maxY - 1 && (rect.minX...rect.maxX).contains(NSEvent.mouseLocation.x) else { return }
                    let peek = UserDefaults.standard.bool(forKey: "peekOnHover") && MusicService.shared.isPlaying
                    model.expand(peek ? .music : nil)
                }
            } else { hoverTask?.cancel(); hoverTask = nil }
        } else {
            hoverTask?.cancel(); hoverTask = nil
            if rect.insetBy(dx: -24, dy: -24).contains(p) || model.pinnedOpen { leaveTask?.cancel(); leaveTask = nil }
            else if leaveTask == nil {
                leaveTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    defer { self?.leaveTask = nil }
                    guard !Task.isCancelled, let self, !model.pinnedOpen,
                          !self.controller.shapeRectOnScreen.insetBy(dx: -24, dy: -24).contains(NSEvent.mouseLocation) else { return }
                    model.collapse()
                }
            }
        }
    }


    /// A real drag-and-drop session changes the drag pasteboard; dragging a window does not (its contents are stale).
    private var isDataDrag: Bool { NSPasteboard(name: .drag).changeCount != dragPasteboardCount }

    /// Dragging a file toward the notch opens the shelf; dragging a window toward it shows snap zones.
    private func setupDragToShelf() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.dragPasteboardCount = NSPasteboard(name: .drag).changeCount; self.shake.reset() } }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let model = NotchModel.shared, p = NSEvent.mouseLocation
                    // A file dragged onto the island must reach it, so the window takes the drag while the pointer is over it.
                    self.controller.updateMouseRouting(at: p)
                    if self.isDataDrag {
                        guard !model.expanded else { return }
                        let pb = NSPasteboard(name: .drag)
                        guard pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
                        let shaken = UserDefaults.standard.object(forKey: "shakeToOpen") as? Bool ?? true && self.shake.add(p, at: Date())
                        if shaken || self.controller.shapeRectOnScreen.insetBy(dx: -30, dy: -30).contains(p) { model.pinnedOpen = true; self.shelfPinned = true; model.expand(.shelf) }
                    } else if Preferences.snapZones.value, !model.expanded {
                        let r = self.controller.shapeRectOnScreen
                        if SnapZones.shared.visible { SnapZones.shared.update(mouse: p) }
                        else if p.y >= r.maxY - 36, abs(p.x - r.midX) < 260 { SnapZones.shared.show() }
                        if SnapZones.shared.visible, p.y < r.maxY - 220 { _ = SnapZones.shared.finish() }
                    }
                }
            }
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if SnapZones.shared.visible, let zone = SnapZones.shared.finish() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { WindowSnap.snap(zone) } }
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { if self.shelfPinned { self.shelfPinned = false; NotchModel.shared.pinnedOpen = false } } }
        } as Any)
    }
}
