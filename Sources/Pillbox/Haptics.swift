import Foundation
import AppKit
import SwiftUI

/// A light tap of the trackpad when the island opens or closes (opt-in, Settings › Island).
enum Haptics {
    static let key = "hapticIsland"
    @MainActor static func tap() {
        guard UserDefaults.standard.bool(forKey: key) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: Auto-collapse after inactivity
