import AppKit
import SwiftUI
import SQLite3
import AVFoundation
import PDFKit
import ImageIO

extension SelfTest {
    static func updateVersions() {
        check("update: compares versions numerically", UpdateCheck.isNewer("v0.10.0", than: "0.9.9") && !UpdateCheck.isNewer("0.3.1", than: "0.3.1") && UpdateCheck.isNewer("1.0", than: "0.9.9") && !UpdateCheck.isNewer("0.3", than: "0.3.1"))
        check("update: only offers a github.com https page", UpdateCheck.releasePage(from: ["html_url": "https://github.com/Arrows78/Pillbox/releases/tag/v1"]) != nil && UpdateCheck.releasePage(from: ["html_url": "https://evil.example/x"]) == nil && UpdateCheck.releasePage(from: ["html_url": "http://github.com/x"]) == nil)
    }

    static func updater() {
        let json: [String: Any] = ["tag_name": "v1.2.0", "html_url": "https://github.com/Arrows78/Pillbox/releases/tag/v1.2.0",
                                   "assets": [["name": "Pillbox-1.2.0.zip", "browser_download_url": "https://github.com/Arrows78/Pillbox/releases/download/v1.2.0/Pillbox-1.2.0.zip"],
                                              ["name": "Pillbox-1.2.0.zip.sha256", "browser_download_url": "http://evil.example/x.sha256"]]]
        let rel = Updater.release(from: json)
        // The checksum asset is on another host, so it is dropped and the release carries no checksum URL.
        check("updater: release parsing keeps https github assets, and drops a checksum on another host", rel?.version == "1.2.0" && rel?.zip?.lastPathComponent == "Pillbox-1.2.0.zip" && rel?.sha == nil && rel?.page != nil)

        // Fails closed: a download without its checksum is refused before anything is unpacked.
        let fm = FileManager.default
        let zip = fm.temporaryDirectory.appendingPathComponent("pillbox-selftest-\(UUID().uuidString).zip")
        let work = fm.temporaryDirectory.appendingPathComponent("pillbox-selftest-\(UUID().uuidString)", isDirectory: true)
        try? Data(count: 2000).write(to: zip)
        defer { try? fm.removeItem(at: zip); try? fm.removeItem(at: work) }
        let refused = Updater.download(zip: zip, sha: nil, version: "1.2.0", into: work)
        var missing = false
        if case .failure(.checksumMissing) = refused { missing = true }
        check("updater: a download without a checksum is refused", missing, "\(refused)")

        check("updater: shasum line digest and SHA-256", Updater.digest(in: "ab" + String(repeating: "cd", count: 31) + "  Pillbox.zip\n")?.count == 64 && Updater.digest(in: "short  x") == nil
              && Updater.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        check("updater: due once a day when enabled", DailyCheck.due(enabled: true, last: nil, now: Date()) && !DailyCheck.due(enabled: false, last: nil, now: Date())
              && DailyCheck.due(enabled: true, last: Date().addingTimeInterval(-90000), now: Date()) && !DailyCheck.due(enabled: true, last: Date().addingTimeInterval(-3600), now: Date()))
    }

    static func brewCheck() {
        check("brew: outdated names parsed, chatter skipped", BrewUpdates.parse("==> Checking\nnode\n  git \nWarning: x\n") == ["node", "git"] && BrewUpdates.parse("").isEmpty)
    }
}
