import Foundation
import AppKit
import SwiftUI
import WebKit

/// The island theme. The raw values are the strings stored under "islandTheme".
enum IslandTheme: String, CaseIterable, Identifiable {
    case black, graphite, glass, accent
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    static var current: IslandTheme { IslandTheme(rawValue: Preferences.islandTheme.value) ?? .black }
}

/// The collapsed pill is always black so it melts into the notch; the open panel follows the theme.
struct IslandBackground: View {
    let expanded: Bool
    @AppStorage("islandTheme") private var theme = IslandTheme.black

    var body: some View {
        let r: CGFloat = expanded ? 28 : 12
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
        ZStack {
            if expanded && theme == .glass {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.4))
            } else {
                shape.fill(.black)
                if expanded && theme == .graphite { shape.fill(Color.white.opacity(0.10)) }
                if expanded && theme == .accent { shape.fill(Color.accentColor.opacity(0.30)) }
            }
        }
        .overlay {
            // A faint lit edge gives the open panel some depth against dark wallpapers.
            if expanded { shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5) }
        }
    }
}

// MARK: Gestures on the pill
