import AppKit
import Foundation
import SwiftUI

struct RemindersTab: View {
    @ObservedObject var rem = RemindersService.shared
    @ObservedObject var model = NotchModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        if !rem.authorized {
            EmptyState(symbol: "checklist", title: "Pillbox needs access to your reminders", actionTitle: "Allow", tint: .blue) { PermissionsCenter.shared.request(.reminders) }
        } else {
            VStack(spacing: Design.gap) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
                    TextField("Add a reminder, e.g. call mum tomorrow at 9am", text: $rem.draft).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                        .onSubmit { rem.add() }
                        .keepsIslandOpen(while: focused, in: model)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Design.card, in: RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous).strokeBorder(Design.hairline, lineWidth: 0.5))
                if rem.items.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "Nothing to do", message: "Type a reminder above, with a date like tomorrow at 9am")
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(rem.items) { r in
                                HStack(spacing: 8) {
                                    Button { rem.complete(r) } label: { Image(systemName: "circle").foregroundStyle(Design.secondary) }.buttonStyle(.plain).accessibilityLabel("Complete")
                                    Text(r.title).lineLimit(1)
                                    Spacer()
                                    if let d = r.due { Text(d, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(r.overdue ? .red : Design.secondary) }
                                }
                                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 5).rowCard()
                                .contextMenu { Button("Complete") { rem.complete(r) } }
                            }
                        }
                    }
                }
            }
        }
    }
}
