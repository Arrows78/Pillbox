import SwiftUI

/// One set of surfaces, hairlines and controls shared by every tab, so the island reads as a single piece.
enum DS {
    static let card = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.08)
    static let radius: CGFloat = 12
}

extension Tab {
    /// Accent of the tab: tints its selected icon in the bar.
    var tint: Color {
        switch self {
        case .home: .white
        case .music: .pink
        case .timer: .orange
        case .stocks: .green
        case .ai: .purple
        case .pulls: .teal
        case .reminders: .blue
        case .notifications: .red
        case .notes: .yellow
        case .clipboard: .mint
        case .shelf: .cyan
        case .launcher: .indigo
        case .terminal: .green
        }
    }
}

/// Icon of the tab bar: tinted capsule when selected, soft highlight under the pointer.
struct TabBarButton: View {
    let tab: Tab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13, weight: .semibold))
                if selected {
                    Text(tab.title).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                }
            }
            .padding(.horizontal, selected ? 12 : 0)
            .frame(minWidth: 34, minHeight: 26)
            .foregroundStyle(selected ? tab.tint : .white.opacity(hovering ? 0.9 : 0.5))
                .background(selected ? tab.tint.opacity(0.22) : .white.opacity(hovering ? 0.08 : 0), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Filled capsule button: `tint` for the main action, neutral otherwise.
struct PillButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(tint ?? Color.white.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Segmented control in the island's style: the selection slides from one option to the next.
struct PillSegmented<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    var tint: Color = .orange
    let label: (T) -> LocalizedStringKey
    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(selection == option ? .white : .white.opacity(0.6))
                        .background {
                            if selection == option { Capsule().fill(tint).matchedGeometryEffect(id: "selection", in: slide) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(2)
        .background(DS.card, in: Capsule())
    }
}

extension View {
    /// Rounded surface with a hairline edge, the island's "card".
    func surface(padding: CGFloat = 10, radius: CGFloat = DS.radius) -> some View {
        self.padding(padding)
            .background(DS.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.hairline, lineWidth: 0.5))
    }
}
