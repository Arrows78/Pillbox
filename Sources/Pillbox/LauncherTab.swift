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

/// The search above the launcher: case-insensitive substring of the name, blank shows everything.
enum LauncherFilter {
    static func matches(_ name: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }

    static func filter<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
        items.filter { matches(name($0), query: query) }
    }
}

/// Columns and height shared by the app and shortcut tiles, so both pages show the same tile.
private let tileColumns = [GridItem(.adaptive(minimum: 84, maximum: 96), spacing: Design.gap)]
private let tileHeight: CGFloat = 78

struct LauncherTab: View {
    @ObservedObject var model = NotchModel.shared
    @State private var page = LauncherPage.apps
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Design.gap) {
            TextField("Search", text: $query).pillField().focused($focused).frame(width: 300)
                .keepsIslandOpen(while: focused, in: model)
            PillSegmented(options: [LauncherPage.apps, .shortcuts, .actions], selection: $page, tint: Tab.launcher.tint) { $0.title }.frame(width: 300)
            switch page {
            case .apps: AppsGrid(query: query)
            case .shortcuts: ShortcutsGrid(query: query)
            case .actions: LauncherActionsGrid(query: query)
            }
        }
    }
}

struct ShortcutsGrid: View {
    @ObservedObject var svc = ShortcutsService.shared
    var query = ""
    var body: some View {
        ScrollView {
            if svc.names.isEmpty { EmptyState(symbol: "bolt", title: "No shortcuts found. Create some in the Shortcuts app.").padding(.top, 12) }
            LazyVGrid(columns: tileColumns, spacing: Design.gap) {
                ForEach(LauncherFilter.filter(svc.names, query: query) { $0 }, id: \.self) { n in
                    Button { svc.run(n) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: svc.running == n ? "hourglass" : "bolt.fill").font(.system(size: 22)).foregroundStyle(.orange).frame(width: 46, height: 46)
                            Text(verbatim: n).font(Design.caption).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.middle).padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity).frame(height: tileHeight)
                        .rowCard(radius: Design.tileRadius)
                    }.buttonStyle(.plain)
                }
            }
        }.onAppear { svc.refresh() }
    }
}

/// The Actions page: `ActionsGrid` (QuickActions.swift) with the search applied.
struct LauncherActionsGrid: View {
    @ObservedObject var store = QuickActionsStore.shared
    var query = ""
    var body: some View {
        ScrollView {
            if store.actions.isEmpty { Text("Add shell commands, links and web mini-apps in Settings › Quick actions").font(Design.label).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                ForEach(LauncherFilter.filter(store.actions, query: query) { $0.name }) { a in
                    Button { store.run(a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: a.kind == .shell ? "terminal" : a.kind == .web ? "macwindow" : "link").foregroundStyle(.orange)
                            Text(verbatim: a.name).lineLimit(1)
                        }.font(Design.label).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
                        .rowCard()
                    }.buttonStyle(.plain).contextMenu { Button("Remove") { store.remove(a) } }
                }
            }
        }
    }
}

struct AppsGrid: View {
    @ObservedObject var store = LauncherStore.shared
    @State private var dragging: String?
    var query = ""

    private var shown: [String] { LauncherFilter.filter(store.paths, query: query) { Self.name($0) } }

    private static func name(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    var body: some View {
        ScrollView {
            if store.paths.isEmpty {
                Text("Pin the apps you open most with +, drag to reorder").font(Design.label).foregroundStyle(Design.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 2)
            }
            LazyVGrid(columns: tileColumns, spacing: Design.gap) {
                ForEach(shown, id: \.self) { path in
                    VStack(spacing: 3) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 46, height: 46)
                        Text(Self.name(path))
                            .font(Design.caption).lineLimit(1).minimumScaleFactor(0.75).truncationMode(.middle).padding(.horizontal, 4)
                    }
                    .frame(maxWidth: .infinity).frame(height: tileHeight)
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
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Design.secondary).frame(maxWidth: .infinity).frame(height: tileHeight)
                }.buttonStyle(.plain).rowCard(radius: Design.tileRadius).hoverTip(localized("Add an app")).accessibilityLabel("Add an app")
            }
        }
    }
}
