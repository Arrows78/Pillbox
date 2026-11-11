import SwiftUI

/// What Home shows in its middle column and its quick tiles, chosen in Settings › Tabs and menu bar.
enum HomeLayout {
    static let cardsKey = "homeCards", tilesKey = "homeTiles", gaugesKey = "homeGauges"
    static let cardSlots = 2, tileSlots = 6, gaugeSlots = 3

    /// A ring in the gauge row.
    enum Gauge: String, CaseIterable, Identifiable {
        case cpu, memory, disk, battery
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cpu: localized("CPU")
            case .memory: localized("Memory")
            case .disk: localized("Disk")
            case .battery: localized("Battery")
            }
        }
    }

    static let defaultGauges: [Gauge] = [.cpu, .memory, .battery]

    static func gauges(_ stored: String?) -> [Gauge] {
        parse(stored, slots: gaugeSlots, defaults: defaultGauges)
    }

    /// The boot disk's used share and its free space, read when Home draws. Nil when the system will not say.
    static var diskUsed: Double {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0 else { return 0 }
        return 1 - Double(free) / Double(total)
    }

    static var diskFree: String {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage else { return "" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    /// A card of the middle column.
    enum Card: String, CaseIterable, Identifiable {
        case nowPlaying, upNext, recentIslands
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nowPlaying: localized("Now playing")
            case .upNext: localized("Up next")
            case .recentIslands: localized("Recent islands")
            }
        }
    }

    /// A one-click tile.
    enum Tile: String, CaseIterable, Identifiable {
        case awake, color, capture, mute, mirror, focus, record, dictate, palette, eyes, lyrics, settings
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .awake: "cup.and.saucer.fill"
            case .color: "eyedropper"
            case .capture: "camera.viewfinder"
            case .mute: "mic.slash.fill"
            case .mirror: "video.fill"
            case .focus: "timer"
            case .record: "record.circle"
            case .dictate: "mic.fill"
            case .palette: "command"
            case .eyes: "eye"
            case .lyrics: "text.quote"
            case .settings: "gearshape"
            }
        }

        /// The short name under the tile.
        var title: String {
            switch self {
            case .awake: "Awake"
            case .color: "Color"
            case .capture: "Capture"
            case .mute: "Mute"
            case .mirror: "Mirror"
            case .focus: "Focus"
            case .record: "Record"
            case .dictate: "Dictate"
            case .palette: "Palette"
            case .eyes: "Eyes"
            case .lyrics: "Lyrics"
            case .settings: "Settings"
            }
        }
    }

    static let defaultCards: [Card] = [.nowPlaying, .upNext]
    static let defaultTiles: [Tile] = [.awake, .color, .capture, .mute, .mirror, .focus]

    /// The stored choice, read leniently: unknown names are skipped and missing slots take the defaults, so an old
    /// or hand-edited value always gives a full layout.
    static func parse<T: RawRepresentable>(_ stored: String?, slots: Int, defaults: [T]) -> [T] where T.RawValue == String {
        let chosen = (stored ?? "").split(separator: ",").compactMap { T(rawValue: String($0)) }
        return (0..<slots).map { i in i < chosen.count ? chosen[i] : defaults[i] }
    }

    static var cards: [Card] { parse(UserDefaults.standard.string(forKey: cardsKey), slots: cardSlots, defaults: defaultCards) }
    static var tiles: [Tile] { parse(UserDefaults.standard.string(forKey: tilesKey), slots: tileSlots, defaults: defaultTiles) }

    static func set(_ values: [some RawRepresentable<String>], key: String) {
        UserDefaults.standard.set(values.map(\.rawValue).joined(separator: ","), forKey: key)
    }
}

/// Settings › Tabs and menu bar › Home: one picker per card and per tile.
struct HomeLayoutSettings: View {
    @AppStorage(HomeLayout.cardsKey) private var cardsRaw = ""
    @AppStorage(HomeLayout.tilesKey) private var tilesRaw = ""
    @AppStorage(HomeLayout.gaugesKey) private var gaugesRaw = ""

    var body: some View {
        let cards = HomeLayout.parse(cardsRaw, slots: HomeLayout.cardSlots, defaults: HomeLayout.defaultCards)
        let tiles = HomeLayout.parse(tilesRaw, slots: HomeLayout.tileSlots, defaults: HomeLayout.defaultTiles)
        let gauges = HomeLayout.gauges(gaugesRaw)
        SettingsCard(title: "Home") {
            SettingsRow(title: "Cards, gauges and tiles", subtitle: "What the Home tab shows in its middle column, its rings and its quick tiles.") {
                Button("Reset") { cardsRaw = ""; tilesRaw = ""; gaugesRaw = "" }.controlSize(.small)
                    .disabled(cardsRaw.isEmpty && tilesRaw.isEmpty && gaugesRaw.isEmpty)
            }
            ForEach(0..<HomeLayout.gaugeSlots, id: \.self) { i in
                SettingsRow(title: LocalizedStringKey(localized("Ring %d", i + 1))) {
                    Picker("", selection: Binding(get: { gauges[i] }, set: { var g = gauges; g[i] = $0; gaugesRaw = g.map(\.rawValue).joined(separator: ",") })) {
                        ForEach(HomeLayout.Gauge.allCases) { Text(verbatim: $0.title).tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
            }
            ForEach(0..<HomeLayout.cardSlots, id: \.self) { i in
                SettingsRow(title: LocalizedStringKey(localized("Card %d", i + 1))) {
                    Picker("", selection: Binding(get: { cards[i] }, set: { var c = cards; c[i] = $0; cardsRaw = c.map(\.rawValue).joined(separator: ",") })) {
                        ForEach(HomeLayout.Card.allCases) { Text(verbatim: $0.title).tag($0) }
                    }.labelsHidden().frame(width: 170)
                }
            }
            ForEach(0..<HomeLayout.tileSlots, id: \.self) { i in
                SettingsRow(title: LocalizedStringKey(localized("Tile %d", i + 1))) {
                    Picker("", selection: Binding(get: { tiles[i] }, set: { var t = tiles; t[i] = $0; tilesRaw = t.map(\.rawValue).joined(separator: ",") })) {
                        ForEach(HomeLayout.Tile.allCases) { tile in Label(localized(tile.title), systemImage: tile.symbol).tag(tile) }
                    }.labelsHidden().frame(width: 170)
                }
            }
        }
    }
}
