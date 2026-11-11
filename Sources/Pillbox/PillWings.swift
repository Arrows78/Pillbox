import SwiftUI

/// Everything a wing of the pill can show. The first seven can be picked in Settings; the rest are built-in
/// live content (alerts, the timer and track while live, the stocks quote and the idle animation).
enum WingItem: String, CaseIterable, Identifiable, Sendable {
    case clock, battery, date, weather, nextEvent, track, timer
    case recording, cleaning, call, build, downloads, privacy, caffeine, stocks, lottie

    var id: String { rawValue }

    /// What Settings offers for a wing, in menu order (without "none").
    static let choices: [WingItem] = [.clock, .battery, .date, .weather, .nextEvent, .track, .timer]
    /// The stored values Settings can hold: "none" plus each choice's raw value.
    static let settingValues: [String] = ["none"] + choices.map(\.rawValue)

    /// The choice a stored setting names, or nil for "none" and anything unknown.
    static func configured(_ stored: String) -> WingItem? {
        choices.first { $0.rawValue == stored }
    }

    var title: String {
        switch self {
        case .clock: localized("Clock")
        case .battery: localized("Battery")
        case .date: localized("Date")
        case .weather: localized("Weather")
        case .nextEvent: localized("Next event")
        case .track: localized("Current track")
        case .timer: localized("Timer")
        default: rawValue
        }
    }
}

enum WingSide: Sendable { case left, right }

/// One place an item may take a wing: which item, on which side, how important, and whether it is live now.
struct WingSlot: Equatable, Sendable {
    let item: WingItem
    let side: WingSide
    let priority: Int
    let live: Bool
}

/// Decides what the two wings show. There is one list of slots; each wing takes the live slot with the highest
/// priority on its side. One slot per wing means at most two items on the pill.
enum WingLayout {
    /// The built-in live content, highest priority first. Alerts come first, then the user's choice (`userRank`),
    /// then the timer and the track, which are shown on their own unless the user picked something for that wing.
    static let builtIn: [(item: WingItem, side: WingSide, priority: Int)] = [
        (.recording, .left, 100), (.recording, .right, 100),
        (.cleaning, .left, 95), (.cleaning, .right, 95),
        (.call, .left, 90), (.call, .right, 90),
        (.build, .left, 85), (.build, .right, 85),
        (.downloads, .left, 80), (.downloads, .right, 80),
        (.privacy, .left, 75),
        (.timer, .left, 65), (.timer, .right, 65),
        (.track, .left, 60), (.track, .right, 60),
        (.caffeine, .left, 55), (.caffeine, .right, 55),
        (.stocks, .right, 57),
        (.lottie, .right, 10),
    ]

    /// The priority of the item a user picked for a wing: below the alerts, above the timer and the track.
    static let userRank = 70

    /// The item each wing shows. Nil on a side with no live slot.
    static func choose(_ slots: [WingSlot]) -> (left: WingItem?, right: WingItem?) {
        func pick(_ side: WingSide) -> WingItem? {
            var best: WingSlot?
            for slot in slots where slot.side == side && slot.live {
                if best == nil || slot.priority > best!.priority { best = slot }
            }
            return best?.item
        }
        return (pick(.left), pick(.right))
    }

    /// The slots for the collapsed pill (`resting` false) or the resting pill (`resting` true), with their live state now.
    /// The resting pill has no built-in content: only what the user picked.
    @MainActor static func slots(left: WingItem?, right: WingItem?, resting: Bool) -> [WingSlot] {
        var out: [WingSlot] = []
        if !resting {
            out += builtIn.map { WingSlot(item: $0.item, side: $0.side, priority: $0.priority, live: isLive($0.item, $0.side, resting: false)) }
        }
        if let left { out.append(WingSlot(item: left, side: .left, priority: userRank, live: isLive(left, .left, resting: resting))) }
        if let right { out.append(WingSlot(item: right, side: .right, priority: userRank, live: isLive(right, .right, resting: resting))) }
        return out
    }

    /// The collapsed pill's wings for the Settings choices `left` and `right` (raw values, "none" for nothing).
    @MainActor static func live(left: String, right: String) -> (left: WingItem?, right: WingItem?) {
        choose(slots(left: WingItem.configured(left), right: WingItem.configured(right), resting: false))
    }

    /// The resting pill's wings for the Settings choices `left` and `right`.
    @MainActor static func resting(left: String, right: String) -> (left: WingItem?, right: WingItem?) {
        choose(slots(left: WingItem.configured(left), right: WingItem.configured(right), resting: true))
    }

    /// Whether an item has something to show on a side right now. Read from the services, so it is main-actor work.
    @MainActor static func isLive(_ item: WingItem, _ side: WingSide, resting: Bool) -> Bool {
        let music = MusicService.shared, timer = TimerService.shared, caffeine = CaffeineService.shared
        switch item {
        case .clock, .battery, .date: return true
        case .weather: return WeatherService.shared.temperature != nil
        case .nextEvent: return CalendarService.shared.next != nil
        case .track: return resting ? music.hasTrack : (music.hasTrack && music.isPlaying)
        case .timer: return timer.isActive
        case .recording: return ScreenRecorder.shared.recording
        case .cleaning: return CleaningLock.shared.active
        case .call: return CallMonitor.shared.call != nil
        case .build: return BuildWatcher.shared.since != nil
        case .downloads: return !DownloadProgress.shared.items.isEmpty
        case .privacy: return PrivacyService.shared.live
        case .caffeine: return side == .left ? caffeine.active : (caffeine.active && caffeine.until != nil)
        case .stocks:
            let stocks = StocksService.shared
            return stocks.pinned.flatMap { stocks.quotes[$0] } != nil
        case .lottie: return LiveState.lottiePath != nil
        }
    }
}

/// One wing's content. Renders nothing for a nil item.
struct WingItemView: View {
    let item: WingItem?
    let side: WingSide
    var resting = false

    @ObservedObject var recorder = ScreenRecorder.shared
    @ObservedObject var downloads = DownloadProgress.shared
    @ObservedObject var build = BuildWatcher.shared
    @ObservedObject var calls = CallMonitor.shared
    @ObservedObject var cleaning = CleaningLock.shared
    @ObservedObject var privacy = PrivacyService.shared
    @ObservedObject var timer = TimerService.shared
    @ObservedObject var music = MusicService.shared
    @ObservedObject var caffeine = CaffeineService.shared
    @ObservedObject var stocks = StocksService.shared
    @ObservedObject var calendar = CalendarService.shared
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var battery = BatteryService.shared

    var body: some View {
        if let item { content(item) }
    }

    @ViewBuilder private func content(_ item: WingItem) -> some View {
        switch item {
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
        case .battery:
            HStack(spacing: 3) {
                Image(systemName: battery.pluggedIn ? "battery.100percent.bolt" : battery.level <= 20 ? "battery.25percent" : "battery.75percent")
                    .font(Design.caption).foregroundStyle(battery.level <= 20 && !battery.pluggedIn ? .red : .white.opacity(0.8))
                Text(verbatim: "\(battery.level)%").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
            }
        case .date:
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day()).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
        case .weather:
            if let t = weather.temperature {
                HStack(spacing: 3) {
                    Image(systemName: weather.symbol).font(Design.caption).foregroundStyle(.white.opacity(0.8))
                    Text(verbatim: "\(t)°").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                }
            }
        case .nextEvent:
            if let next = calendar.next {
                Text(verbatim: next.title).font(Design.captionStrong).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
        case .track:
            if resting {
                if music.hasTrack { Text(verbatim: music.title).font(Design.captionStrong).foregroundStyle(.white.opacity(0.85)).lineLimit(1) }
            } else if side == .left {
                if music.hasTrack && music.isPlaying {
                    if let art = music.artwork { Image(nsImage: art).resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5)) }
                    else { Image(systemName: "music.note").foregroundStyle(.white) }
                }
            } else if music.hasTrack && music.isPlaying {
                Equalizer()
            }
        case .timer:
            if side == .left {
                if timer.isActive {
                    if let e = Mascot.emoji(for: Mascot.current, progress: timer.progress) { Text(e).font(.system(size: 14)) }
                    else { Image(systemName: "timer").font(Design.titleStrong).foregroundStyle(.orange) }
                }
            } else if timer.isActive {
                Text(timer.display).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.orange)
            }
        case .recording:
            if side == .left { RecordingDot() }
            else if let r = recorder.since { Text(r, style: .timer).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.red).frame(width: 52) }
        case .cleaning:
            if side == .left { if cleaning.active { Image(systemName: "lock.fill").foregroundStyle(.yellow) } }
            else if cleaning.active { Text("\(cleaning.remaining)s").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.yellow) }
        case .call:
            if side == .left { if calls.call != nil { Image(systemName: "phone.fill").font(Design.body).foregroundStyle(.green) } }
            else if let c = calls.call { Text(c.since, style: .timer).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.green).frame(width: 52) }
        case .build:
            if side == .left { if build.since != nil { Image(systemName: "hammer.fill").font(Design.body).foregroundStyle(.blue) } }
            else if let s = build.since { Text(s, style: .timer).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.blue).frame(width: 52) }
        case .downloads:
            if side == .left { if !downloads.items.isEmpty { Image(systemName: "arrow.down.circle.fill").font(Design.title).foregroundStyle(.blue) } }
            else if let d = downloads.items.first { Text(verbatim: DownloadProgress.size(d.bytes)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.blue) }
        case .privacy:
            if privacy.live {
                HStack(spacing: 4) {
                    if privacy.micLive { Image(systemName: "mic.fill").foregroundStyle(.orange) }
                    if privacy.cameraLive { Image(systemName: "video.fill").foregroundStyle(.green) }
                }.font(Design.label)
            }
        case .caffeine:
            if side == .left { if caffeine.active { Image(systemName: "cup.and.saucer.fill").font(Design.title).foregroundStyle(.orange) } }
            else if caffeine.active, let u = caffeine.until { Text(u, style: .timer).font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange) }
        case .stocks:
            if let sym = stocks.pinned, let q = stocks.quotes[sym] {
                Text(String(format: "%@%.1f%%", q.change >= 0 ? "+" : "", q.change * 100))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(q.change >= 0 ? .green : .red)
            }
        case .lottie:
            if let path = LiveState.lottiePath { LottieIdle(path: path).frame(width: 28, height: 24).clipped() }
        }
    }
}

/// The two wings of the pill: one item on each side, or nothing. The notch sits between them.
struct WingRow: View {
    let left: WingItem?
    let right: WingItem?
    var resting = false
    @ObservedObject var model = NotchModel.shared

    var body: some View {
        HStack(spacing: 0) {
            WingItemView(item: left, side: .left, resting: resting).frame(width: NotchModel.wing, alignment: .center)
            Spacer(minLength: model.geometry.width)
            WingItemView(item: right, side: .right, resting: resting).frame(width: NotchModel.wing, alignment: .center)
        }
        .frame(maxHeight: model.geometry.height)
        .accessibilityElement(children: .contain)
    }
}
