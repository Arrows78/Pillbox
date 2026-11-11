import Foundation
import AppKit
import Lottie
import SwiftUI

struct LottieIdle: NSViewRepresentable {
    let path: String
    func makeNSView(context: Context) -> NSView {
        let v = LottieAnimationView(filePath: path)
        v.loopMode = .loop; v.contentMode = .scaleAspectFit
        v.animationSpeed = max(Preferences.lottieSpeed.value, 0.1)
        v.play()
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: Timer mascots (original emoji, no third-party artwork)

enum Mascot: String, CaseIterable, Identifiable {
    case none, cat, rocket, plant, flame, robot
    var id: String { rawValue }
    var emoji: String? { ["cat": "🐱", "rocket": "🚀", "plant": "🌱", "flame": "🔥", "robot": "🤖"][rawValue] }
    var title: String { rawValue.capitalized }
    static var current: Mascot { Mascot(rawValue: UserDefaults.standard.string(forKey: "mascot") ?? "none") ?? .none }

    /// The mascot grows with the session: seed, sprout, then the full emoji for the plant; others just pulse.
    static func emoji(for mascot: Mascot, progress: Double) -> String? {
        guard let e = mascot.emoji else { return nil }
        guard mascot == .plant else { return e }
        return progress < 0.34 ? "🌱" : progress < 0.67 ? "🌿" : "🌳"
    }
}

// MARK: Desktop widgets
