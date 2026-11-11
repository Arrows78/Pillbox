import AppKit
import Foundation
import SwiftUI

struct HomeTab: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var stats = StatsService.shared
    @ObservedObject var calendar = CalendarService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var audio = AudioControl.shared
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var batteryLog = BatteryLog.shared
    @ObservedObject var recorder = ScreenRecorder.shared
    @ObservedObject var dictation = DictationService.shared
    @State private var batteryChart = false
    @AppStorage(HomeLayout.cardsKey) private var cardsRaw = ""
    @AppStorage(HomeLayout.tilesKey) private var tilesRaw = ""
    @AppStorage(HomeLayout.gaugesKey) private var gaugesRaw = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 34, weight: .semibold, design: .rounded))
                }
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.system(size: 12)).foregroundStyle(.secondary)
                if let temperature = weather.temperature {
                    Label("\(temperature)° \(weather.summary)\(weather.city.isEmpty ? "" : " · " + weather.city)", systemImage: weather.symbol)
                        .font(.system(size: 11)).symbolRenderingMode(.multicolor).foregroundStyle(.secondary).lineLimit(1)
                } else if weather.denied {
                    Label("Weather needs Location access", systemImage: "location.slash").font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
                }
                HourlyStrip()
                Spacer(minLength: 4)
                NetworkLine(down: stats.down, up: stats.up, samples: stats.netHistory)
                ForEach(stats.bluetooth, id: \.self) { line in
                    Label { Text(verbatim: line) } icon: { Image(systemName: "airpodspro") }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                if !stats.devices.isEmpty {
                    Label(stats.devices.map { "\($0.name) \($0.percent)%" }.joined(separator: " · "), systemImage: "battery.75percent")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 190, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(Array(HomeLayout.parse(cardsRaw, slots: HomeLayout.cardSlots, defaults: HomeLayout.defaultCards).enumerated()), id: \.offset) { _, card in
                    switch card {
                    case .nowPlaying: HomeNowPlaying()
                    case .upNext: HomeUpNext()
                    case .recentIslands: HomeRecentIslands()
                    }
                }
            }.frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(HomeLayout.gauges(gaugesRaw).enumerated()), id: \.offset) { _, item in
                        gaugeView(item)
                    }
                }
                .opacity(batteryChart ? 0 : 1)
                .overlay {   // same footprint as the gauges, so the column never grows
                    if batteryChart {
                        BatteryChartCard(samples: batteryLog.history, level: battery.level, remaining: batteryLog.remaining,
                                         health: batteryLog.health, hasBattery: batteryLog.hasBattery)
                            .contentShape(Rectangle()).onTapGesture { batteryChart = false }
                            .accessibilityAddTraits(.isButton).accessibilityAction { batteryChart = false }
                    }
                }
                let tiles = HomeLayout.parse(tilesRaw, slots: HomeLayout.tileSlots, defaults: HomeLayout.defaultTiles)
                VStack(spacing: 8) {
                    ForEach([0, 3], id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row..<row + 3, id: \.self) { i in tile(tiles[i]) }
                        }
                    }
                }
            }.frame(width: 280)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    /// One gauge of the row; the battery keeps its tap for the history chart.
    @ViewBuilder private func gaugeView(_ item: HomeLayout.Gauge) -> some View {
        switch item {
        case .cpu: gauge("CPU", stats.cpu, .green)
        case .memory: gauge("RAM", stats.memory, .blue)
        case .disk: gauge("Disk", HomeLayout.diskUsed, .orange, detail: HomeLayout.diskFree)
        case .battery:
            gauge("Batt", Double(battery.level) / 100, battery.level < 20 ? .red : .yellow, icon: battery.pluggedIn ? "bolt.fill" : nil, detail: batteryLog.remaining)
                .contentShape(Rectangle()).onTapGesture { batteryChart = true }.hoverTip(localized("Battery history"))
                .accessibilityAddTraits(.isButton).accessibilityAction { batteryChart = true }
        }
    }

    private func gauge(_ name: LocalizedStringKey, _ fraction: Double, _ tint: Color, icon: String? = nil, detail: String? = nil) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(tint.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                if let icon { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint) }
                else { Text("\(Int(fraction * 100))").font(.system(size: 11, weight: .semibold, design: .rounded)) }
            }.frame(width: 46, height: 46)
            (Text(name) + Text(verbatim: detail.map { " · " + $0 } ?? "")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(card, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
        .accessibilityElement(children: .ignore).accessibilityLabel(Text(name)).accessibilityValue("\(Int(fraction * 100))%")
    }

    /// One quick tile, with its action and whether it is on.
    @ViewBuilder private func tile(_ tile: HomeLayout.Tile) -> some View {
        let title = LocalizedStringKey(tile.title)
        switch tile {
        case .awake:
            quick(tile.symbol, title, active: caffeine.active) { caffeine.toggle() }
                .contextMenu {
                    Button("30 minutes") { caffeine.start(minutes: 30) }
                    Button("1 hour") { caffeine.start(minutes: 60) }
                    Button("2 hours") { caffeine.start(minutes: 120) }
                    Button("Until 6 pm") { caffeine.start(until: 18) }
                    Button("Until turned off") { caffeine.start() }
                    if caffeine.active { Divider(); Button("Turn off") { caffeine.stop() } }
                }
        case .color: quick(tile.symbol, title) { SystemActions.pickColor() }
        case .capture: quick(tile.symbol, title) { SystemActions.captureArea() }
        case .mute: quick(tile.symbol, title, active: audio.micMuted) { audio.toggleMic() }
        case .mirror: quick(tile.symbol, title) { CameraMirror.shared.toggle() }
        case .focus: quick(tile.symbol, title, active: timer.running) { timer.mode = .focus; timer.toggle() }
        case .record: quick(tile.symbol, title, active: recorder.recording) { recorder.toggle() }
        case .dictate: quick(tile.symbol, title, active: dictation.active) { dictation.toggle() }
        case .palette: quick(tile.symbol, title) { PaletteController.shared.show() }
        case .eyes: quick(tile.symbol, title) { EyeBreaks.shared.begin() }
        case .lyrics: quick(tile.symbol, title) { LyricsScreen.shared.show() }
        case .settings: quick(tile.symbol, title) { SettingsWindow.show() }
        }
    }

    private func quick(_ symbol: String, _ title: LocalizedStringKey, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17)).frame(height: 20)
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(active ? Color.orange.opacity(0.30) : card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(active ? Color.orange.opacity(0.6) : Design.hairline, lineWidth: 0.5))
        }.buttonStyle(.plain)
    }
}

/// Home card: the current track with its controls, or a way to start the music.
struct HomeNowPlaying: View {
    @ObservedObject var music = MusicService.shared

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let a = music.artwork { Image(nsImage: a).resizable() }
                else { Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "music.note").foregroundStyle(.secondary)) }
            }
            .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: music.hasTrack ? music.title : localized(music.automationDenied == nil ? "Nothing playing" : "Music is open")).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(music.hasTrack ? 1 : 0.8)
                Text(verbatim: music.hasTrack ? music.artist : (music.automationDenied.map { localized("Allow Automation for %@ in Settings", $0.rawValue) } ?? localized("Start Spotify or Apple Music"))).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(music.hasTrack ? 1 : 2)
                if music.hasTrack {
                    ProgressBar(value: music.position, total: music.duration) { music.seek(to: $0) }.frame(height: 4).padding(.top, 4)
                }
            }
            Spacer(minLength: 4)
            if music.hasTrack {
                HStack(spacing: 14) {
                    Button { music.previous() } label: { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
                    Button { music.playPause() } label: { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)) }
                        .accessibilityLabel(LocalizedStringKey(music.isPlaying ? "Pause" : "Play"))
                    Button { music.next() } label: { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
                }.buttonStyle(.plain).font(.system(size: 12))
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { NotchModel.shared.tab = .music }
    }
}

/// Home card: the next three timed events today and tomorrow, with Join for video calls.
struct HomeUpNext: View {
    @ObservedObject var agenda = AgendaModel.shared
    @ObservedObject var calendar = CalendarService.shared

    var body: some View {
        let upcoming = Array(agenda.events.filter { !$0.allDay && $0.end > Date() }.prefix(3))
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if upcoming.isEmpty {
                Text(agenda.denied ? "Calendar access is off" : "No upcoming events").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(upcoming) { e in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: e.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Group {
                            if e.start > Date() { Text(e.start, style: .relative) } else { Text("Now") }
                        }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let url = e.join {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Join", systemImage: "video.fill") }.buttonStyle(PillButtonStyle(tint: .green))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { NotchModel.shared.tab = .calendar }
        .onAppear { agenda.refresh() }
        .onChange(of: calendar.next?.start) { _, _ in agenda.refresh() }
    }
}
