import Foundation
import AppKit
import SwiftUI
import ServiceManagement

/// "Copy" that turns into "Copied" for a moment.
struct CopyButton: View {
    let text: () -> String
    var title = "Copy"
    @State private var copied = false

    var body: some View {
        Button(LocalizedStringKey(copied ? "Copied" : title)) {
            Pasteboard.copy(text())
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }.controlSize(.small)
    }
}

/// A shortcut drawn as keycaps.
struct Keycaps: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(String(k)).font(.system(size: 12, weight: .medium, design: .rounded)).frame(minWidth: 22, minHeight: 22)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

struct DetachToggle: View {
    let tab: Tab
    @State private var on: Bool
    init(tab: Tab) { self.tab = tab; _on = State(initialValue: MenuBarDetach.wanted.contains(tab)) }
    var body: some View {
        SettingsToggle("Show \(tab.title) in the menu bar", isOn: $on)
            .onChange(of: on) { _, v in
                var set = MenuBarDetach.wanted
                if v { set.insert(tab) } else { set.remove(tab) }
                MenuBarDetach.setWanted(set)
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let now = MenuBarDetach.wanted.contains(tab)   // an import or a reset changes it behind this switch
                if now != on { on = now }
            }
    }
}

/// Settings › Tabs and menu bar › Tabs: one row per tab, with arrows to move it and a switch to hide it.
/// Fewer tabs make a shorter bar, and ⌘1–9 follow the ones left, in this order. Home stays first and always shown.
struct TabsPicker: View {
    @AppStorage(Tab.hiddenKey) private var hidden = ""
    @AppStorage(Tab.orderKey) private var order = ""

    var body: some View {
        let set = Tab.hidden(from: hidden)
        let movable = Array(Tab.ordered(from: order).dropFirst())   // Home is first and stays there
        SettingsRow(title: "Shown in the island", subtitle: "Move the tabs with the arrows and turn off the ones you never open. Home always stays first.") {
            HStack {
                Button("Default order") { order = "" }.disabled(order.isEmpty)
                Button("Show all") { hidden = "" }.disabled(set.isEmpty)
            }.controlSize(.small)
        }
        ForEach(Array(movable.enumerated()), id: \.element) { index, tab in
            SettingsRow(title: LocalizedStringKey(tab.title)) {
                HStack(spacing: 6) {
                    Button { move(movable, index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0).accessibilityLabel(Text("Move up"))
                    Button { move(movable, index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == movable.count - 1).accessibilityLabel(Text("Move down"))
                    Toggle("", isOn: Binding(get: { !set.contains(tab) }, set: { on in
                        var s = set
                        if on { s.remove(tab) } else { s.insert(tab) }
                        hidden = Tab.allCases.filter(s.contains).map(\.rawValue).joined(separator: ",")
                        if !on, NotchModel.shared.tab == tab { NotchModel.shared.tab = .home }
                    })).labelsHidden().toggleStyle(.switch).tint(SettingsStyle.accent)
                        .accessibilityLabel(Text(verbatim: tab.title))
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    private func move(_ tabs: [Tab], _ index: Int, by step: Int) {
        var list = tabs
        let target = index + step
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        order = list.map(\.rawValue).joined(separator: ",")
    }
}
