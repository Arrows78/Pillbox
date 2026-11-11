import AppKit
import Foundation
import SwiftUI

/// The launcher's three pages: pinned apps, Apple Shortcuts, and built-in actions.
enum LauncherPage: Hashable {
    case apps, shortcuts, actions

    var title: LocalizedStringKey {
        switch self {
        case .apps: return "Apps"
        case .shortcuts: return "Shortcuts"
        case .actions: return "Actions"
        }
    }
}

struct LauncherTab: View {
    @State private var page = LauncherPage.apps
    var body: some View {
        VStack(spacing: Design.gap) {
            PillSegmented(options: [LauncherPage.apps, .shortcuts, .actions], selection: $page, tint: Tab.launcher.tint) { $0.title }.frame(width: 300)
            switch page {
            case .apps: AppsGrid()
            case .shortcuts: ShortcutsGrid()
            case .actions: ActionsGrid()
            }
        }
    }
}

struct ShortcutsGrid: View {
    @ObservedObject var svc = ShortcutsService.shared
    var body: some View {
        ScrollView {
            if svc.names.isEmpty { EmptyState(symbol: "bolt", title: "No shortcuts found. Create some in the Shortcuts app.").padding(.top, 12) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                ForEach(svc.names, id: \.self) { n in
                    Button { svc.run(n) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: svc.running == n ? "hourglass" : "bolt.fill").foregroundStyle(.orange)
                            Text(verbatim: n).lineLimit(1)
                        }.font(Design.label).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
                        .rowCard()
                    }.buttonStyle(.plain)
                }
            }
        }.onAppear { svc.refresh() }
    }
}

struct AppsGrid: View {
    @ObservedObject var store = LauncherStore.shared
    @State private var dragging: String?

    var body: some View {
        ScrollView {
            if store.paths.isEmpty {
                Text("Pin the apps you open most with +, drag to reorder").font(Design.label).foregroundStyle(Design.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: Design.gap)], spacing: Design.gap) {
                ForEach(store.paths, id: \.self) { path in
                    VStack(spacing: 3) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 46, height: 46)
                        Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
                            .font(Design.caption).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.middle).padding(.horizontal, 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: 78)
                    .rowCard(radius: Design.tileRadius)
                    .onTapGesture { store.launch(path) }
                    .onDrag { dragging = path; return NSItemProvider(object: path as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { _ in
                        if let d = dragging { store.move(d, onto: path) }
                        return true
                    }
                    .contextMenu {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                        Button("Remove", role: .destructive) { store.remove(path) }
                    }
                }
                Button { store.add() } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Design.secondary).frame(maxWidth: .infinity).frame(height: 78)
                }.buttonStyle(.plain).rowCard(radius: Design.tileRadius).hoverTip(localized("Add an app")).accessibilityLabel("Add an app")
            }
        }
    }
}
