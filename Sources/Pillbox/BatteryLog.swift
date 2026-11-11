import AppKit
import Charts
@preconcurrency import IOBluetooth
import IOKit
import IOKit.ps
import SwiftUI

// MARK: Battery history, health, time remaining and drain warning

struct BatterySample: Codable, Equatable {
    var t: Date
    var level: Int
    var charging: Bool
}

enum BatteryMath {
    static let keep: TimeInterval = 48 * 3600
    static let interval: TimeInterval = 300

    /// Samples of the last `keep` seconds, oldest first.
    static func trimmed(_ s: [BatterySample], now: Date = Date(), keep: TimeInterval = keep) -> [BatterySample] {
        s.filter { now.timeIntervalSince($0.t) <= keep && $0.t <= now.addingTimeInterval(60) }.sorted { $0.t < $1.t }
    }

    /// Percentage points lost per 10 minutes over the trailing run off the charger in `window`; nil with under 8 minutes of data.
    static func drainPer10Min(_ s: [BatterySample], now: Date = Date(), window: TimeInterval = 900) -> Double? {
        var run: [BatterySample] = []
        for x in s.reversed() where now.timeIntervalSince(x.t) <= window {
            if x.charging { break }
            run.insert(x, at: 0)
        }
        guard let a = run.first, let b = run.last else { return nil }
        let dt = b.t.timeIntervalSince(a.t)
        guard dt >= 480 else { return nil }
        return Double(a.level - b.level) / dt * 600
    }

    /// Apple Silicon reports AppleRawMaxCapacity in mAh and MaxCapacity as a percentage; Intel reports MaxCapacity in mAh.
    static func healthPercent(rawMax: Int?, max maximum: Int?, design: Int?) -> Int? {
        let pct: (Int, Int) -> Int = { min(Int((Double($0) / Double($1) * 100).rounded()), 100) }
        if let d = design, d > 0 {
            if let r = rawMax, r > 0 { return pct(r, d) }
            if let m = maximum, m > 100 { return pct(m, d) }
        }
        return maximum.flatMap { (1...100).contains($0) ? $0 : nil }
    }

    /// "3:20" for an estimate in seconds; nil while macOS is still computing it (negative values).
    static func remaining(_ seconds: TimeInterval) -> String? {
        guard seconds > 0 else { return nil }
        let m = Int(seconds / 60)
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

enum BatteryHealth {
    static func hasBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return list.contains { (IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
    }

    /// Maximum capacity as System Settings shows it, and the cycle count; nil on Macs without a battery. Slow: call off the main thread.
    static func read() -> (percent: Int, cycles: Int?)? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler"); p.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        if (try? p.run()) != nil {
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            if let r = parse(d) { return r }
        }
        return registry()
    }

    static func parse(_ data: Data) -> (percent: Int, cycles: Int?)? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = (root["SPPowerDataType"] as? [[String: Any]])?.lazy.compactMap({ $0["sppower_battery_health_info"] as? [String: Any] }).first,
              let pct = (info["sppower_battery_health_maximum_capacity"] as? String).flatMap({ Int($0.filter(\.isNumber)) }) else { return nil }
        return (pct, info["sppower_battery_cycle_count"] as? Int)
    }

    /// From the IOKit registry; recent macOS moves the mAh values into BatteryData.
    static func registry() -> (percent: Int, cycles: Int?)? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        func value(_ k: String) -> Any? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
        let data = value("BatteryData") as? [String: Any] ?? [:]
        func int(_ k: String) -> Int? { value(k) as? Int ?? data[k] as? Int }
        guard let p = BatteryMath.healthPercent(rawMax: int("AppleRawMaxCapacity"), max: int("MaxCapacity"), design: int("DesignCapacity")) else { return nil }
        return (p, int("CycleCount"))
    }
}

@MainActor
final class BatteryLog: ObservableObject {
    static let shared = BatteryLog()
    static let file = "battery-history.json"
    @Published private(set) var history: [BatterySample] = []
    @Published private(set) var remaining: String?
    @Published private(set) var health: (percent: Int, cycles: Int?)?
    private(set) var hasBattery = false
    private var recent: [BatterySample] = []
    private var timer: Timer?
    private var lastWarning = Date.distantPast
    /// When the health was last read; it is read again once an hour, whatever the number of samples.
    private var lastHealth = Date.distantPast

    func start() {
        hasBattery = BatteryHealth.hasBattery()
        guard hasBattery, timer == nil else { return }
        history = BatteryMath.trimmed(Store.load(Self.file, as: [BatterySample].self) ?? [])
        refreshHealth()
        let b = BatteryService.shared
        record(level: b.level, charging: b.charging, pluggedIn: b.pluggedIn)
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: BatteryMath.interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
    }

    private func sample() {
        let b = BatteryService.shared
        if let last = history.last, Date().timeIntervalSince(last.t) < BatteryMath.interval - 30 { return }
        history = BatteryMath.trimmed(history + [BatterySample(t: Date(), level: b.level, charging: b.charging)])
        Store.save(history, Self.file)
        // Time-based: the history is trimmed to 48 h, so its count stops growing and a count-based check would stall.
        if Date().timeIntervalSince(lastHealth) >= 3600 { refreshHealth() }
    }

    private func refreshHealth() {
        lastHealth = Date()
        DispatchQueue.global(qos: .utility).async {
            let h = BatteryHealth.read()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.health = h } }
        }
    }

    /// Called on every power source change.
    func record(level: Int, charging: Bool, pluggedIn: Bool) {
        guard hasBattery else { return }
        let est = IOPSGetTimeRemainingEstimate()
        remaining = pluggedIn ? nil : BatteryMath.remaining(est)
        let now = Date()
        recent = BatteryMath.trimmed(recent + [BatterySample(t: now, level: level, charging: charging || pluggedIn)], now: now, keep: 1800)
        let threshold = UserDefaults.standard.integer(forKey: "drainAlert")
        guard threshold > 0, !pluggedIn, now.timeIntervalSince(lastWarning) > 1800,
              let rate = BatteryMath.drainPer10Min(recent, now: now), rate >= Double(threshold) else { return }
        lastWarning = now
        NotchModel.shared.show(Activity(symbol: "battery.25", title: localized("Battery draining fast"),
                                        subtitle: localized("%d%% · −%d%%/10 min", level, Int(rate.rounded())), tint: .orange, duration: 5))
    }
}

/// The last 24 hours of battery level, with charging periods as a green strip along the bottom.
struct BatteryChartCard: View {
    var samples: [BatterySample]
    var level: Int
    var remaining: String?
    var health: (percent: Int, cycles: Int?)?
    var hasBattery = true
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if hasBattery { Text(verbatim: "\(level)%").font(.system(size: 11, weight: .semibold, design: .rounded)) }
                if let r = remaining { Text("\(r) left").foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if let h = health {
                    Text(h.cycles.map { localized("Health %d%% · %d cycles", h.percent, $0) } ?? localized("Health %d%%", h.percent)).foregroundStyle(.secondary)
                }
            }.font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
            if !hasBattery {
                Text("No battery").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let day = samples.filter { now.timeIntervalSince($0.t) <= 86_400 }
                Chart {
                    ForEach(day, id: \.t) { s in
                        AreaMark(x: .value("Time", s.t), y: .value("Level", s.level)).foregroundStyle(.yellow.opacity(0.18)).interpolationMethod(.monotone)
                        LineMark(x: .value("Time", s.t), y: .value("Level", s.level)).foregroundStyle(.yellow).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.monotone)
                    }
                    ForEach(day.filter(\.charging), id: \.t) { s in
                        RectangleMark(xStart: .value("Time", s.t), xEnd: .value("Time", s.t.addingTimeInterval(BatteryMath.interval)), yStart: .value("Level", 0), yEnd: .value("Level", 6))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
                .chartXScale(domain: now.addingTimeInterval(-86_400)...now)
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine().foregroundStyle(.white.opacity(0.12)) } }
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel(format: .dateTime.hour()).font(.system(size: 7)) } }
                .overlay { if day.count < 2 { Text("Collecting data…").font(.system(size: 9)).foregroundStyle(.secondary) } }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Design.card, in: RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Network history
