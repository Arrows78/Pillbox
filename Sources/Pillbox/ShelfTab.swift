import AppKit
import Foundation
import SwiftUI

struct ShelfTab: View {
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        Group {
        if shelf.items.isEmpty {
            EmptyState(symbol: "tray.and.arrow.down", title: "Drop files on the notch to stash them", message: "They stay here, ready to drag out or send",
                       actionTitle: "Add files…", tint: Tab.shelf.tint) { shelf.browse() }
        } else {
            VStack(spacing: Design.gap) {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Design.gap)], spacing: Design.gap) {
                        ForEach(shelf.items) { ShelfCell(item: $0) }
                        Button { shelf.browse() } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(Design.secondary)
                                .frame(maxWidth: .infinity).frame(height: ShelfCell.height)
                        }.buttonStyle(.plain).rowCard(radius: Design.tileRadius).hoverTip(localized("Add files…")).accessibilityLabel("Add files…")
                    }
                }
                HStack(spacing: 6) {
                    let target = shelf.selection.isEmpty ? shelf.items : shelf.selected
                    Button { shelf.airDrop(target) } label: { Label("AirDrop", systemImage: "dot.radiowaves.left.and.right") }.buttonStyle(PillButtonStyle(tint: Tab.shelf.tint.opacity(0.55)))
                    Button("Zip / Unzip") { shelf.zipOrUnzip(target) }.buttonStyle(PillButtonStyle())
                    let kinds = Array(Set(target.flatMap { ConvertTarget.targets(for: $0.url) })).sorted { $0.rawValue < $1.rawValue }
                    if !kinds.isEmpty {
                        Menu {
                            ForEach(kinds) { k in Button(LocalizedStringKey(k.rawValue)) { shelf.convert(target.filter { ConvertTarget.targets(for: $0.url).contains(k) }, to: k) } }
                        } label: { Text("Convert").font(Design.labelStrong) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 5).background(Color.white.opacity(0.12), in: Capsule())
                    }
                    Button("Reveal") { shelf.reveal(target) }.buttonStyle(PillButtonStyle())
                    if target.count == 1, let one = target.first, Annotator.canAnnotate(one.url) { Button("Annotate") { Annotator.open(one.url) }.buttonStyle(PillButtonStyle()) }
                    Spacer(minLength: 6)
                    Text(verbatim: ShelfService.summary(count: shelf.items.count, selected: shelf.selection.count))
                        .font(Design.label).foregroundStyle(Design.secondary).lineLimit(1).fixedSize()
                    IconButton(symbol: "trash", label: localized("Clear the shelf")) { shelf.clear() }
                }
            }
        }
        }
        .onAppear { shelf.purgeMissing() }
    }
}

struct ShelfCell: View {
    static let height: CGFloat = 100
    let item: ShelfItem
    @ObservedObject var shelf = ShelfService.shared

    var body: some View {
        let selected = shelf.selection.contains(item.id)
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().frame(width: 48, height: 48)
            Text(verbatim: item.name).font(Design.caption).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(.horizontal, 6).frame(maxWidth: .infinity).frame(height: Self.height)
        .rowCard(radius: Design.tileRadius, selected: selected ? Tab.shelf.tint.opacity(0.3) : nil)
        .overlay(alignment: .topTrailing) {
            if selected { Image(systemName: "checkmark.circle.fill").font(Design.body).foregroundStyle(Tab.shelf.tint).padding(5) }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .onTapGesture { if selected { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) } }
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .contextMenu {
            Button("Open with default app") { NSWorkspace.shared.open(item.url) }
            Button("Reveal in Finder") { shelf.reveal([item]) }
            if Annotator.canAnnotate(item.url) { Button("Annotate") { Annotator.open(item.url) } }
            Button("AirDrop") { shelf.airDrop([item]) }
            Button("Copy path") { shelf.copyPaths([item]) }
            Button("Copy file") { shelf.copyFiles([item]) }
            Button("Share…") { shelf.share([item]) }
            Divider()
            Button("Remove from shelf", role: .destructive) { shelf.remove([item.id]) }
        }
    }
}
