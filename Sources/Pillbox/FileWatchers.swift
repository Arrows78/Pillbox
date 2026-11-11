import Foundation
import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import EventKit
import SwiftUI

/// Watches a folder and reports each new entry once (macOS writes screenshots and downloads as temporary files first).
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    let dir: URL
    private let onNew: (URL) -> Void
    nonisolated static let temporarySuffixes: Set<String> = ["crdownload", "download", "part", "opdownload", "tmp"]

    init(dir: URL, onNew: @escaping (URL) -> Void) { self.dir = dir; self.onNew = onNew }

    func start() {
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        dispatchSource.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        dispatchSource.setCancelHandler { close(fd) }
        dispatchSource.resume(); source = dispatchSource
    }

    func stop() { source?.cancel(); source = nil }

    /// Reports entries that appeared since the last call, skipping hidden and temporary files.
    func changed() {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        for name in now.subtracting(known).sorted() where !name.hasPrefix(".") && !Self.temporarySuffixes.contains((name as NSString).pathExtension.lowercased()) {
            onNew(dir.appendingPathComponent(name))
        }
        known = now
    }
}

/// Base for a folder watched from launch: `watch(_:)` starts it, and `found` gets each new entry.
@MainActor
class FolderAlertWatcher {
    private var watcher: FolderWatcher?

    func watch(_ dir: URL) {
        watcher = FolderWatcher(dir: dir) { [weak self] url in self?.found(url) }
        watcher?.start()
    }

    func found(_ url: URL) {}
}

@MainActor
final class DownloadsWatcher: FolderAlertWatcher {
    static let shared = DownloadsWatcher()

    func start() {
        watch(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    override func found(_ url: URL) {
        guard Defaults.bool("downloadAlerts", default: true) else { return }
        NotchModel.shared.show(Activity(symbol: "arrow.down.circle.fill", title: localized("Download finished"), subtitle: url.lastPathComponent, tint: .blue,
                                        actionTitle: localized("Reveal"), action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }, duration: 5))
    }
}

/// New screenshots become an island and are staged on the shelf, ready to drag into any app.
@MainActor
final class ScreenshotWatcher: FolderAlertWatcher {
    static let shared = ScreenshotWatcher()

    static var screenshotFolder: URL {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: (configured as NSString?)?.expandingTildeInPath ?? NSHomeDirectory() + "/Desktop")
    }

    /// macOS tags real screenshots with this extended attribute, whatever the language of the file name.
    static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    func start() {
        watch(Self.screenshotFolder)
    }

    override func found(_ url: URL) {
        // The tag lands a moment after the file appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in MainActor.assumeIsolated { self?.handle(url) } }
    }

    func handle(_ url: URL) {
        guard Defaults.bool("screenshotShelf", default: true), Self.isScreenshot(url) else { return }
        ShelfService.shared.add([url])
        NotchModel.shared.show(Activity(symbol: "camera.viewfinder", title: localized("Screenshot ready"), subtitle: localized("On the shelf, drag it anywhere"), tint: .green,
                                        actionTitle: localized("Copy"), action: {
            if let img = NSImage(contentsOf: url) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img]) }
        }, duration: 5))
    }
}

/// Offers a one-tap eject when a removable drive is plugged in.
@MainActor
final class DriveWatcher {
    static let shared = DriveWatcher()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { DriveWatcher.shared.mounted(url) }
        })
    }

    static func isEjectable(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey])
        return (v?.volumeIsEjectable == true || v?.volumeIsRemovable == true) && v?.volumeIsInternal != true
    }

    private func mounted(_ url: URL) {
        guard Defaults.bool("driveEject", default: true), Self.isEjectable(url) else { return }
        NotchModel.shared.show(Activity(symbol: "externaldrive.fill", title: localized("Drive connected"), subtitle: url.lastPathComponent, tint: .white,
                                        actionTitle: localized("Eject"), action: {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: localized("Safe to disconnect"), subtitle: url.lastPathComponent, tint: .green))
            } catch {
                NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: localized("Could not eject"), subtitle: url.lastPathComponent, tint: .orange))
            }
        }, duration: 8))
    }
}
