import Foundation
import AppKit
import SwiftUI

extension NSPanel {
    /// The look the floating panels share: see-through with a shadow, the content draws its own background.
    func styleAsOverlay(level: NSWindow.Level) {
        isOpaque = false; backgroundColor = .clear; hasShadow = true; self.level = level
    }
}
