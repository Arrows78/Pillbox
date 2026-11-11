import AppKit
import Foundation
import SwiftUI

struct NotificationsTab: View {
    @ObservedObject var mirror = NotificationMirror.shared
    @State private var app: String?

    /// Bundle identifiers present, most recent first, for the filter chips.
    nonisolated static func apps(in items: [NotificationItem]) -> [String] {
        var seen = Set<String>(); return items.map(\.app).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func name(_ bundleID: String) -> String { BlockedAppsStore.name(bundleID) }

    var body: some View {
        Group {
            if let items = mirror.items, items.isEmpty {
                EmptyState(symbol: "bell.slash", title: "No notifications")
            } else if let items = mirror.items {
                let apps = Self.apps(in: items), shown = items.filter { app == nil || $0.app == app }
                VStack(spacing: Design.gap) {
                    if apps.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                FilterChip(symbol: "tray.full", label: localized("All"), selected: app == nil, tint: .red) { app = nil }
                                ForEach(apps, id: \.self) { id in
                                    Button { app = app == id ? nil : id } label: {
                                        HStack(spacing: 4) {
                                            if let i = BlockedAppsStore.icon(id) { Image(nsImage: i).resizable().frame(width: 14, height: 14) }
                                            Text(verbatim: Self.name(id)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                            Text(verbatim: "\(items.filter { $0.app == id }.count)").font(.system(size: 9)).foregroundStyle(Design.secondary)
                                        }
                                        .padding(.horizontal, 8).frame(height: 22)
                                        .foregroundStyle(app == id ? Color.red : .white.opacity(0.75))
                                        .background(app == id ? Color.red.opacity(0.22) : .white.opacity(0.06), in: Capsule())
                                    }.buttonStyle(.plain).accessibilityAddTraits(app == id ? .isSelected : [])
                                }
                            }
                        }.frame(height: 22)
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(shown) { n in
                                HStack(spacing: 8) {
                                    if let i = BlockedAppsStore.icon(n.app) { Image(nsImage: i).resizable().frame(width: 22, height: 22) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack {
                                            Text(verbatim: n.title.isEmpty ? Self.name(n.app) : n.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                            Spacer()
                                            Text(n.date, style: .relative).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                        if !n.body.isEmpty { Text(verbatim: n.body).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                                        if n.app == MessageReply.app { SMSReplyField(sender: n.sender) }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                                .rowCard()
                                .onTapGesture { if n.app != MessageReply.app { open(n.app) } }
                                .contextMenu {
                                    Button("Open the app") { open(n.app) }
                                    if let code = NotificationFeed.verificationCode(in: n.body) { Button(LocalizedStringKey(localized("Copy code %@", code))) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } }
                                    Button("Copy text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString([n.title, n.body].filter { !$0.isEmpty }.joined(separator: "\n"), forType: .string) }
                                }
                            }
                        }
                    }
                }
            } else if mirror.queryFailed {
                EmptyState(symbol: "exclamationmark.triangle", title: "Could not read notifications")
            } else {
                EmptyState(symbol: "bell.badge", title: "Reading notifications needs Full Disk Access", actionTitle: "Open Settings", tint: .red) { PermissionsCenter.shared.openSettings(.fullDisk) }
            }
        }
        .onAppear { mirror.refresh() }
        // A filter for an app that no longer has rows would hide every row with no chip left to clear it.
        .onChange(of: Self.apps(in: mirror.items ?? [])) { _, remaining in
            if let selected = app, !remaining.contains(selected) { app = nil }
        }
    }

    private func open(_ bundleID: String) {
        AppLauncher.open(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID), named: Self.name(bundleID))
    }
}
