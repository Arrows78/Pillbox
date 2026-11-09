import AppKit
import SwiftUI
import Combine

/// Counts of one day. Only numbers: which keys were pressed is never looked at.
struct ActivityDay: Codable, Equatable {
    var day: String
    var keys = 0
    var clicks = 0
    var metres = 0.0
}

/// The last seven days of counts, oldest first.
struct ActivityLog: Codable, Equatable {
    static let keep = 7
    var days: [ActivityDay] = []

    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Keys of the seven days ending on `date`, oldest first.
    static func week(ending date: Date, calendar: Calendar = .current) -> [String] {
        (0..<keep).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: date).map { key($0, calendar: calendar) } }
    }

    mutating func add(keys: Int, clicks: Int, metres: Double, on date: Date, calendar: Calendar = .current) {
        let k = Self.key(date, calendar: calendar)
        if let i = days.firstIndex(where: { $0.day == k }) {
            days[i].keys += keys; days[i].clicks += clicks; days[i].metres += metres
        } else {
            days.append(ActivityDay(day: k, keys: keys, clicks: clicks, metres: metres))
        }
        trim(to: date, calendar: calendar)
    }

    /// Drops every day older than the last seven.
    mutating func trim(to date: Date, calendar: Calendar = .current) {
        let week = Set(Self.week(ending: date, calendar: calendar))
        days = days.filter { week.contains($0.day) }.sorted { $0.day < $1.day }
    }

    /// Seven entries ending on `date`, with zeros for days without activity.
    func lastWeek(ending date: Date, calendar: Calendar = .current) -> [ActivityDay] {
        Self.week(ending: date, calendar: calendar).map { k in days.first { $0.day == k } ?? ActivityDay(day: k) }
    }

    func today(_ date: Date = Date(), calendar: Calendar = .current) -> ActivityDay {
        let k = Self.key(date, calendar: calendar)
        return days.first { $0.day == k } ?? ActivityDay(day: k)
    }
}

private func activityTap(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let location = event.location
    let repeated = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    MainActor.assumeIsolated { ActivityCounter.shared.record(type, at: location, repeated: repeated) }
    return Unmanaged.passUnretained(event)
}

/// Counts clicks, keystrokes and how far the pointer travels, per day. Off by default; needs Input Monitoring.
/// A listen-only event tap: events are never changed, and only totals are kept (no key, no position).
@MainActor
final class ActivityCounter: ObservableObject {
    static let shared = ActivityCounter()
    static let file = "activity.json"
    /// Millimetres per point used when a display does not report its physical size.
    nonisolated static let fallbackMillimetresPerPoint = 0.26
    /// A jump longer than this (a pointer warped between screens) is not travel.
    nonisolated static let maxStep = 1500.0

    @Published private(set) var log = Store.load(ActivityCounter.file, as: ActivityLog.self) ?? ActivityLog()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var flushTimer: Timer?
    private var pending = (keys: 0, clicks: 0, metres: 0.0)
    private var last: CGPoint?
    private var displays: [(bounds: CGRect, mmPerPoint: Double)] = []
    private var warned = false
    private var screensObserver: Any?
    private var flushes = 0

    var enabled: Bool { UserDefaults.standard.bool(forKey: "activityCounter") }
    var running: Bool { tap != nil }

    nonisolated static func millimetresPerPoint(physicalWidth mm: Double, pointWidth: Double) -> Double {
        mm > 0 && pointWidth > 0 ? mm / pointWidth : fallbackMillimetresPerPoint
    }

    /// Metres travelled from `a` to `b` at `mmPerPoint`; 0 for a jump.
    nonisolated static func metres(from a: CGPoint, to b: CGPoint, mmPerPoint: Double) -> Double {
        let d = hypot(Double(b.x - a.x), Double(b.y - a.y))
        return d > maxStep ? 0 : d * mmPerPoint / 1000
    }

    nonisolated static func distance(_ m: Double) -> String {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit; f.unitStyle = .medium
        f.numberFormatter.maximumFractionDigits = m >= 1000 ? 2 : (m < 10 ? 1 : 0)
        let v: Measurement<UnitLength> = m >= 1000 ? Measurement(value: m / 1000, unit: .kilometers) : Measurement(value: m, unit: .meters)
        return f.string(from: v)
    }

    func apply() { enabled ? start() : stop() }

    private func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask, callback: activityTap, userInfo: nil) else {
            if !warned {
                warned = true
                _ = CGRequestListenEventAccess()
                NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: "Input Monitoring needed", subtitle: "Allow Pillbox to count your activity", tint: .orange,
                                                actionTitle: "Settings", action: { PermissionsCenter.shared.openSettings(.inputMonitoring) }, duration: 6))
            }
            return
        }
        tap = t; source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        measureDisplays()
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ActivityCounter.shared.measureDisplays() }
        }
        flushTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { ActivityCounter.shared.flush() } }
    }

    private func stop() {
        warned = false
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil; last = nil
        flushTimer?.invalidate(); flushTimer = nil
        if let o = screensObserver { NotificationCenter.default.removeObserver(o); screensObserver = nil }
        save()
    }

    private func measureDisplays() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { displays = []; return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        displays = ids.map { id in
            let b = CGDisplayBounds(id)
            return (b, Self.millimetresPerPoint(physicalWidth: Double(CGDisplayScreenSize(id).width), pointWidth: Double(b.width)))
        }
    }

    fileprivate func record(_ type: CGEventType, at p: CGPoint, repeated: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput: if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        case .keyDown: if !repeated { pending.keys += 1 }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: pending.clicks += 1
        default:
            if let l = last {
                let mm = displays.first { $0.bounds.contains(p) }?.mmPerPoint ?? Self.fallbackMillimetresPerPoint
                pending.metres += Self.metres(from: l, to: p, mmPerPoint: mm)
            }
            last = p
        }
    }

    /// Moves the pending counts into the log; written to disk every minute.
    func flush() {
        guard pending.keys > 0 || pending.clicks > 0 || pending.metres > 0 else { return }
        log.add(keys: pending.keys, clicks: pending.clicks, metres: pending.metres, on: Date())
        pending = (0, 0, 0)
        flushes += 1
        if flushes % 12 == 0 { Store.save(log, Self.file) }
    }

    func save() { flush(); Store.save(log, Self.file) }

    /// For `--render` only.
    func preview(_ l: ActivityLog) { log = l }

    func reset() { pending = (0, 0, 0); log = ActivityLog(); Store.save(log, Self.file) }

    func showToday() {
        guard enabled else {
            NotchModel.shared.show(Activity(symbol: "chart.bar.fill", title: "Activity counter is off", tint: .orange, actionTitle: "Turn on", action: {
                UserDefaults.standard.set(true, forKey: "activityCounter")
            }, duration: 5))
            return
        }
        flush()
        let d = log.today()
        NotchModel.shared.show(Activity(symbol: "chart.bar.fill", title: L("%@ keys · %@ clicks", d.keys.formatted(), d.clicks.formatted()),
                                        subtitle: L("%@ of mouse travel", Self.distance(d.metres)), tint: .cyan, duration: 5))
    }
}

enum ActivityMetric: String, CaseIterable, Identifiable {
    case keys, clicks, distance
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .keys: "Keystrokes"; case .clicks: "Clicks"; case .distance: "Distance" }
    }
    var symbol: String {
        switch self { case .keys: "keyboard"; case .clicks: "cursorarrow.click"; case .distance: "arrow.up.and.down.and.arrow.left.and.right" }
    }
    func value(_ d: ActivityDay) -> Double {
        switch self { case .keys: Double(d.keys); case .clicks: Double(d.clicks); case .distance: d.metres }
    }
    func text(_ d: ActivityDay) -> String {
        switch self { case .keys: d.keys.formatted(); case .clicks: d.clicks.formatted(); case .distance: ActivityCounter.distance(d.metres) }
    }
}

/// Today's counts and a seven-day bar chart of one of them. Tap a figure to chart it.
struct ActivityCounterCard: View {
    @ObservedObject var counter = ActivityCounter.shared
    @State private var metric = ActivityMetric.keys
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let week = counter.log.lastWeek(ending: Date())
        let today = week.last ?? ActivityDay(day: "")
        let top = max(week.map(metric.value).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(ActivityMetric.allCases) { m in
                    Button { metric = m } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(m.title, systemImage: m.symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(SettingsStyle.dim).lineLimit(1)
                            Text(verbatim: m.text(today)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 88, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(metric == m ? SettingsStyle.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(week, id: \.day) { d in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(d.day == today.day ? SettingsStyle.accent : SettingsStyle.accent.opacity(0.45))
                            .frame(width: 12, height: max(2, 40 * metric.value(d) / top))
                        Text(verbatim: Self.weekday(d.day)).font(.system(size: 9)).foregroundStyle(SettingsStyle.dim)
                    }
                    .help(metric.text(d))
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
        .padding(12)
        .onReceive(tick) { _ in counter.flush() }
    }

    static func weekday(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: key) else { return "" }
        let w = DateFormatter(); w.setLocalizedDateFormatFromTemplate("EEEEE")
        return w.string(from: d)
    }
}
