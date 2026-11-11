import AppKit

/// Backs up the data Pillbox keeps in Application Support (notes, clipboard history, shelf, snippets, quick actions,
/// and so on) as one zip, and restores it. Preferences have their own file, see Backup.swift; Keychain items stay out.
/// Restoring never deletes what is there: the current folder is moved aside first, and Pillbox must restart to use it.
enum DataBackup {
    static let format = "pillbox-data"
    static let manifestName = "pillbox-data.json"
    private static let folderName = "Pillbox data"

    /// One file of a backup and, when it is a list or an object, how many entries it holds.
    struct Entry: Equatable {
        let name: String
        let items: Int?
    }

    enum Failure: Error { case notABackup, tool(Int32) }

    /// Writes the data folder, with a manifest, to `zip`.
    static func export(to zip: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("pillbox-export-\(UUID().uuidString)", isDirectory: true)
        let root = staging.appendingPathComponent(folderName, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: Store.dir, includingPropertiesForKeys: nil) where !item.lastPathComponent.hasSuffix(".broken") {
            try fm.copyItem(at: item, to: root.appendingPathComponent(item.lastPathComponent))
        }
        let manifest: [String: Any] = ["format": format, "version": 1, "created": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: root.appendingPathComponent(manifestName))
        try? fm.removeItem(at: zip)
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", root.path, zip.path])
    }

    /// Unzips a backup to a temporary folder and checks its manifest. The caller removes the folder's parent when done.
    static func unpack(_ zip: URL) throws -> URL {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("pillbox-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, parent.path])
            let folder = parent.appendingPathComponent(folderName, isDirectory: true)
            let manifestURL = folder.appendingPathComponent(manifestName)
            guard let data = try? Data(contentsOf: manifestURL),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], json["format"] as? String == format else {
                throw Failure.notABackup
            }
            return folder
        } catch {
            try? FileManager.default.removeItem(at: parent)
            throw error
        }
    }

    /// What a backup folder holds, without the manifest: the file names, and the count of entries where it can tell.
    static func entries(in folder: URL) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.map(\.lastPathComponent).filter { $0 != manifestName }.sorted().map { name in
            Entry(name: name, items: itemCount(of: folder.appendingPathComponent(name)))
        }
    }

    /// Replaces the data folder with the backup's. The current one is kept beside it, under a dated name.
    static func restore(from folder: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: Store.dir.path) {
            let aside = Store.dir.deletingLastPathComponent().appendingPathComponent("Pillbox-before-restore-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try fm.moveItem(at: Store.dir, to: aside)
        }
        try fm.copyItem(at: folder, to: Store.dir)
        try? fm.removeItem(at: Store.dir.appendingPathComponent(manifestName))   // the manifest belongs to the backup, not the data
    }

    /// The entries of a list, or of an object, inside a Store file: the envelope's data when it has one.
    static func itemCount(of url: URL) -> Int? {
        guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
              var json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        if let object = json as? [String: Any], object["version"] != nil, let inner = object["data"] { json = inner }
        if let list = json as? [Any] { return list.count }
        if let object = json as? [String: Any] { return object.count }
        return nil
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw Failure.tool(process.terminationStatus) }
    }
}

/// The two backup actions of Settings › General › Backup.
@MainActor
enum DataBackupActions {
    static func backUp() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Pillbox data.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DataBackup.export(to: url)
            NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: localized("Your data is backed up."), tint: .green))
        } catch {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: localized("Could not back up your data"), tint: .orange))
        }
    }

    /// Opens the backup, lists what it holds, and only then replaces the data, on a second confirmation.
    static func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder: URL
        do { folder = try DataBackup.unpack(url) } catch {
            let alert = NSAlert()
            alert.messageText = localized("This file is not a Pillbox data backup")
            alert.runModal(); return
        }
        let parent = folder.deletingLastPathComponent()
        let entries = DataBackup.entries(in: folder)
        let alert = NSAlert()
        alert.messageText = localized("Restore this backup?")
        alert.informativeText = entries.map { e in e.items.map { "\(e.name): \($0)" } ?? e.name }.joined(separator: "\n")
            + "\n\n" + localized("Your current data is kept in a folder beside it. Restart Pillbox to use the restored data.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("Restore"))
        alert.addButton(withTitle: localized("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { try? FileManager.default.removeItem(at: parent); return }
        do {
            try DataBackup.restore(from: folder)
            NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: localized("Data restored. Restart Pillbox to use it."), tint: .green, duration: 5))
        } catch {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: localized("Could not restore the data"), tint: .orange))
        }
        try? FileManager.default.removeItem(at: parent)
    }
}
