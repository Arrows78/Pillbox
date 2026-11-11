import Foundation
import AppKit
import SwiftUI

/// An island the moment the camera turns on. macOS does not say which app opened it: the front app is a best guess,
/// shown as such, and nothing is shown for Pillbox's own mirror.
enum CameraGuard {
    /// Whether the camera island shows, and the app it names as the probable one (nil when it is not known).
    enum Island: Equatable { case hidden, shown(probableApp: String?) }

    static func island(mirrorOpen: Bool, frontName: String?, frontBundle: String?, own: String?) -> Island {
        if mirrorOpen { return .hidden }
        return .shown(probableApp: frontBundle == own ? nil : frontName)
    }

    @MainActor static func cameraStarted() {
        let front = NSWorkspace.shared.frontmostApplication
        guard case .shown(let app) = island(mirrorOpen: CameraMirror.shared.isOpen, frontName: front?.localizedName, frontBundle: front?.bundleIdentifier, own: Bundle.main.bundleIdentifier) else { return }
        NotchModel.shared.show(Activity(symbol: "video.fill", title: localized("Camera turned on"), subtitle: app.map { localized("Probably %@", $0) }, tint: .green,
                                        image: app == nil ? nil : AppIconImage.bitmap(front?.icon), duration: 4))
    }
}

// MARK: Settings
