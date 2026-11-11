import SwiftUI
import Foundation
import AppKit

struct DownloadItem: Equatable { let name: String; let bytes: Int64 }

enum DownloadScan {
    /// Partial downloads in a folder, with their current size (Safari's .download is a folder, so it is summed).
    static func scan(_ dir: URL) -> [DownloadItem] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        // A .tmp file is not a browser download: it is excluded here, as it always was.
        return names.filter { !$0.hasPrefix(".") && FolderWatcher.temporarySuffixes.contains(($0 as NSString).pathExtension.lowercased()) && ($0 as NSString).pathExtension.lowercased() != "tmp" }
            .map { name in
                let url = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                var total: Int64 = 0
                if isDir.boolValue {
                    let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
                    while let f = en?.nextObject() as? URL { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                } else { total = Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0) }
                return DownloadItem(name: ((name as NSString).deletingPathExtension), bytes: total)
            }.sorted { $0.bytes > $1.bytes }
    }
}

@MainActor
final class DownloadProgress: ObservableObject {
    static let shared = DownloadProgress()
    @Published private(set) var items: [DownloadItem] = []
    private var timer: Timer?

    func start() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard Defaults.bool("downloadAlerts", default: true) else { return }
            DispatchQueue.global(qos: .utility).async {
                let found = DownloadScan.scan(dir)
                DispatchQueue.main.async { MainActor.assumeIsolated { if self?.items != found { self?.items = found; NotificationCenter.default.post(name: .notchStateChanged, object: nil) } } }
            }
        }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

// MARK: Build island
