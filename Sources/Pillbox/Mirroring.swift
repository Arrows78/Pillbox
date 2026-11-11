import Foundation
import AppKit
import SwiftUI

enum Mirroring {
    static let key = "hideWhileMirroring"
    /// True when any display is in a mirror set (a projector or a TV showing the same picture).
    static var active: Bool {
        NSScreen.screens.contains { s in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsInMirrorSet(id) != 0
        }
    }
    static var shouldHide: Bool { UserDefaults.standard.bool(forKey: key) && active }
}

// MARK: Swipe the resting notch to change desktop
