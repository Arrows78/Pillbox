import AppKit
import Foundation
import SwiftUI

/// The clipboard tab's two pages: the history of copies, and the saved snippets.
enum ClipboardPage: Hashable { case history, snippets }

struct ClipboardHistory: View {
    @Binding var mode: ClipboardPage
    @ObservedObject var clip = ClipboardService.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: Design.gap) {
            HStack(spacing: Design.gap) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Design.secondary)
                    TextField("Search text and screenshots", text: $clip.query).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                    if !clip.query.isEmpty {
                        Button { clip.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Design.secondary) }.buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(Design.card, in: Capsule()).overlay(Capsule().strokeBorder(Design.hairline, lineWidth: 0.5))
                HStack(spacing: 2) {
                    ForEach(ClipFilter.allCases) { f in
                        FilterChip(symbol: f.symbol, label: localized(f.label), selected: clip.filter == f, tint: .mint) { clip.filter = f }
                    }
                }
                IconButton(symbol: "trash", label: localized("Clear history (pinned items stay)")) { clip.clearUnpinned() }
                ClipboardModePicker(mode: $mode)
            }
            .keepsIslandOpen(while: focused, in: model)
            let items = clip.filtered
            if items.isEmpty {
                if clip.items.isEmpty { EmptyState(symbol: "doc.on.clipboard", title: "Clipboard history is empty", message: "Copy text or an image and it shows up here") }
                else { EmptyState(symbol: "magnifyingglass", title: "No matches", actionTitle: "Show all") { clip.query = ""; clip.filter = .all } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Design.gap) {
                        ForEach(items) { item in ClipCard(item: item) }
                    }.padding(.trailing, 24)
                }.trailingFade()
            }
        }
    }
}

struct ClipboardTab: View {
    @State private var mode = ClipboardPage.history
    var body: some View {
        if mode == .history { ClipboardHistory(mode: $mode) } else { SnippetsView(mode: $mode) }
    }
}

struct ClipboardModePicker: View {
    @Binding var mode: ClipboardPage
    var body: some View {
        PillSegmented(options: [ClipboardPage.history, .snippets], selection: $mode, tint: .mint.opacity(0.45)) { $0 == .history ? "History" : "Snippets" }.frame(width: 190)
    }
}

struct SnippetsView: View {
    @Binding var mode: ClipboardPage
    @ObservedObject var store = SnippetsStore.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: Design.gap) {
                ClipboardModePicker(mode: $mode)
                TextField("Name", text: $store.draftName).pillField().focused($focused)
                TextField("Text to paste", text: $store.draftText, axis: .vertical).lineLimit(2, reservesSpace: true).pillField().focused($focused)
                Button("Save snippet") { store.add() }.buttonStyle(PillButtonStyle(tint: .mint.opacity(0.45)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 220)
            .keepsIslandOpen(while: focused, in: model)
            if store.snippets.isEmpty {
                EmptyState(symbol: "text.quote", title: "No snippets yet", message: "Save text you paste often, then paste it from the palette")
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.snippets) { sn in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sn.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(sn.text).font(.system(size: 10)).foregroundStyle(Design.secondary).lineLimit(1)
                                }
                                Spacer()
                                IconButton(symbol: "trash", label: localized("Delete")) { store.remove(sn) }
                            }
                            .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4).rowCard()
                            .onTapGesture { store.paste(sn) }
                            .contextMenu {
                                Button("Paste") { store.paste(sn) }
                                Button("Delete") { store.remove(sn) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ClipCard: View {
    let item: ClipItem
    @ObservedObject var clip = ClipboardService.shared
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content.frame(width: 156, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading).clipped()
            HStack(spacing: 5) {
                Image(systemName: kindSymbol).foregroundStyle(Design.secondary)
                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                Text(item.date, style: .relative).foregroundStyle(Design.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if hovering {
                    if let u = link { cardButton("safari", localized("Open link")) { NSWorkspace.shared.open(u) } }
                    cardButton(item.pinned ? "pin.slash" : "pin", localized(item.pinned ? "Unpin" : "Pin")) { clip.togglePin(item) }
                    cardButton("trash", localized("Delete")) { clip.remove(item) }
                }
            }.font(.system(size: 9)).frame(height: 14)
        }
        .padding(10).rowCard(radius: 10)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { clip.paste(item) }
        .onTapGesture { clip.copy(item); NotchModel.shared.show(Activity(symbol: "doc.on.doc.fill", title: localized("Copied"), duration: 1.2)) }
        .contextMenu {
            Button("Copy") { clip.copy(item) }
            Button("Paste") { clip.paste(item) }
            if let u = link { Button("Open link") { NSWorkspace.shared.open(u) } }
            if let t = item.text, case .email(let e) = ClipboardService.kind(of: t), let u = URL(string: "mailto:\(e)") {
                Button("Send email") { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button(LocalizedStringKey(item.pinned ? "Unpin" : "Pin")) { clip.togglePin(item) }
            Button("Delete", role: .destructive) { clip.remove(item) }
        }
    }

    private var link: URL? {
        if let t = item.text, case .url(let u) = ClipboardService.kind(of: t) { return u }
        return nil
    }

    private var kindSymbol: String {
        guard let t = item.text else { return ClipFilter.images.symbol }
        switch ClipboardService.kind(of: t) {
        case .url: return ClipFilter.links.symbol
        case .color: return ClipFilter.colors.symbol
        case .email: return "envelope"
        case .plain: return ClipFilter.text.symbol
        }
    }

    private func cardButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 14, height: 14) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel(Text(verbatim: label))
    }

    @ViewBuilder private var content: some View {
        if let img = clip.image(for: item) {
            Image(nsImage: img).resizable().scaledToFill().frame(width: 156).frame(maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let t = item.text {
            switch ClipboardService.kind(of: t) {
            case .color(let swatch, let hex):
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: swatch)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Design.hairline, lineWidth: 0.5))
                        .frame(maxHeight: 96)
                    Text(hex.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced))
                    let rgb = swatch.usingColorSpace(.sRGB) ?? swatch
                    Text(verbatim: "rgb(\(Int(rgb.redComponent * 255)), \(Int(rgb.greenComponent * 255)), \(Int(rgb.blueComponent * 255)))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Design.secondary)
                }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(size: 11)).lineLimit(9)
                    if t.count > 140 { Text("\(t.count) chars · \(t.split(whereSeparator: \.isWhitespace).count) words").font(.system(size: 9)).foregroundStyle(Design.secondary) }
                }
            }
        }
    }
}
