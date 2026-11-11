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
        // The day is measured from the last check: exactly 24 h is due, one second less is not, and a disabled switch never is.
        let now = Date()
        check("updater: the daily check is due at exactly one day, not a second before, and never when disabled",
              DailyCheck.due(enabled: true, last: now.addingTimeInterval(-86_400), now: now) && !DailyCheck.due(enabled: true, last: now.addingTimeInterval(-86_399), now: now)
              && !DailyCheck.due(enabled: false, last: now.addingTimeInterval(-86_400 * 3), now: now))

        // Release parsing: the version drops a leading v, a missing tag gives nothing, and only https github.com downloads are kept.
        let upper = Updater.release(from: ["tag_name": "V2.0", "assets": [["name": "Pillbox-2.0.zip", "browser_download_url": "https://github.com/Arrows78/Pillbox/releases/download/V2.0/Pillbox-2.0.zip"],
                                                                         ["name": "Pillbox-2.0.zip.sha256", "browser_download_url": "https://github.com/Arrows78/Pillbox/releases/download/V2.0/Pillbox-2.0.zip.sha256"]]])
        check("updater: release keeps a github checksum, and strips a capital V from the version", upper?.version == "2.0" && upper?.sha?.lastPathComponent == "Pillbox-2.0.zip.sha256" && upper?.zip != nil)
        check("updater: no tag means no release", Updater.release(from: ["assets": [[String: Any]]()]) == nil && Updater.release(from: ["tag_name": 3]) == nil)
        let noZip = Updater.release(from: ["tag_name": "v1.0", "assets": [["name": "Pillbox-1.0.dmg", "browser_download_url": "https://github.com/x/Pillbox-1.0.dmg"]]])
        let httpZip = Updater.release(from: ["tag_name": "v1.0", "assets": [["name": "Pillbox-1.0.zip", "browser_download_url": "http://github.com/x/Pillbox-1.0.zip"]]])
        check("updater: a release without a zip on https github.com can only be opened, not installed", noZip?.zip == nil && noZip?.version == "1.0" && httpZip?.zip == nil && httpZip?.sha == nil)

        // Each failure says what happened, in the language of the app.
        let messages: [(UpdateError, String)] = [
            (.download, localized("The download failed")),
            (.checksumMissing, localized("The checksum is missing, so the update was not installed")),
            (.checksumMismatch, localized("The checksum does not match")),
            (.save, localized("Could not save the download")),
            (.unpack, localized("Could not unpack the download")),
            (.notPillbox, localized("The archive is not a Pillbox release")),
            (.install, localized("The update could not be installed")),
        ]
        let wrong = messages.filter { $0.0.errorDescription != $0.1 || $0.1.isEmpty }.map { "\($0.0)" }
        check("updater: each update error has its own localized message", wrong.isEmpty && Set(messages.map { $0.1 }).count == 7, "\(wrong)")
    }

    static func brewCheck() {
        check("brew: outdated names parsed, chatter skipped", BrewUpdates.parse("==> Checking\nnode\n  git \nWarning: x\n") == ["node", "git"] && BrewUpdates.parse("").isEmpty)
    }
}
