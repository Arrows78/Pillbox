import Foundation
import AppKit
import SwiftUI

enum SpaceSwipe {
    static let key = "swipeSpaces"
    /// Sends ⌃← or ⌃→, the Mission Control shortcuts, so macOS moves to the neighbouring Space (needs Accessibility).
    @MainActor static func go(left: Bool) {
        guard AXIsProcessTrusted() else {
            NotchModel.shared.show(Activity(symbol: "hand.raised.fill", title: localized("Accessibility needed"), subtitle: localized("Allow Pillbox to switch desktops"), tint: .orange,
                                            actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.accessibility) }, duration: 5))
            return
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: left ? 123 : 124, keyDown: down)
            e?.flags = .maskControl; e?.post(tap: .cghidEventTap)
        }
    }
}
