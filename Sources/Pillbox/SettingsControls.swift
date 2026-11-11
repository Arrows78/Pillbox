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

/// Settings › Island › Tabs: one switch per tab. Fewer tabs make a shorter bar, and ⌘1–9 follow the ones left.
struct TabsPicker: View {
    @AppStorage(Tab.hiddenKey) private var hidden = ""

    var body: some View {
        let set = Tab.hidden(from: hidden)
        SettingsRow(title: "Shown in the island", subtitle: "Turn off the tabs you never open. Home always stays.") {
            Button("Show all") { hidden = "" }.controlSize(.small).disabled(set.isEmpty)
        }
        ForEach(Tab.allCases.filter { $0 != .home }) { tab in
            SettingsRow(title: LocalizedStringKey(tab.title)) {
                Toggle("", isOn: Binding(get: { !set.contains(tab) }, set: { on in
                    var s = set
                    if on { s.remove(tab) } else { s.insert(tab) }
                    hidden = Tab.allCases.filter(s.contains).map(\.rawValue).joined(separator: ",")
                    if !on, NotchModel.shared.tab == tab { NotchModel.shared.tab = .home }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(SettingsStyle.accent)
                    .accessibilityLabel(Text(verbatim: tab.title))
            }
        }
    }
}
