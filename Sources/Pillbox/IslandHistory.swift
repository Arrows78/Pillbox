import SwiftUI

/// The last islands, so one that went by in three seconds can be read again from Home or the menu bar.
/// Kept in memory only: islands can carry a verification code or a message, which should not land on disk.
@MainActor
final class IslandHistory: ObservableObject {
    static let shared = IslandHistory()
    static let limit = 20

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        /// The island it came from, so presenting the same island again does not add it twice.
        let source: UUID
        let symbol: String
        let title: String
        let subtitle: String?
        let date: Date
    }

    @Published private(set) var entries: [Entry] = []

    /// A separate history, for the self-test; the app uses `shared`.
    init() {}

    /// Records an island that was shown. Passing HUDs (volume, brightness, Caps Lock) are not worth keeping:
    /// they have a level bar, or a low priority.
    func record(_ activity: Activity, at date: Date = Date()) {
        guard Self.keeps(activity), !entries.contains(where: { $0.source == activity.id }) else { return }
        entries.insert(Entry(source: activity.id, symbol: activity.symbol, title: activity.title, subtitle: activity.subtitle, date: date), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    func clear() { entries = [] }

    nonisolated static func keeps(_ activity: Activity) -> Bool { activity.inHistory && activity.progress == nil && activity.priority != .low }
}

/// Home card: the latest islands, newest first.
struct HomeRecentIslands: View {
    @ObservedObject var history = IslandHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent islands").font(Design.captionStrong).foregroundStyle(.secondary)
                Spacer()
                if !history.entries.isEmpty {
                    Button("Clear") { history.clear() }.buttonStyle(.plain).font(Design.caption).foregroundStyle(.secondary)
                }
            }
            if history.entries.isEmpty {
                Text("No island yet").font(Design.bodyMedium).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(history.entries.prefix(3)) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.symbol).font(Design.body).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: entry.title).font(Design.bodyMedium).lineLimit(1)
                        Text(entry.date, format: .dateTime.hour().minute()).font(Design.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Design.card, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
    }
}
