import AppKit
import Charts
import IOBluetooth
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
    static func healthPercent(rawMax: Int?, max: Int?, design: Int?) -> Int? {
        let pct: (Int, Int) -> Int = { min(Int((Double($0) / Double($1) * 100).rounded()), 100) }
        if let d = design, d > 0 {
            if let r = rawMax, r > 0 { return pct(r, d) }
            if let m = max, m > 100 { return pct(m, d) }
        }
        return max.flatMap { (1...100).contains($0) ? $0 : nil }
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
        if history.count % 12 == 0 { refreshHealth() }
    }

    private func refreshHealth() {
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
        NotchModel.shared.show(Activity(symbol: "battery.25", title: "Battery draining fast",
                                        subtitle: L("%d%% · −%d%%/10 min", level, Int(rate.rounded())), tint: .orange, duration: 5))
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
                    Text(h.cycles.map { L("Health %d%% · %d cycles", h.percent, $0) } ?? L("Health %d%%", h.percent)).foregroundStyle(.secondary)
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
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Network history

struct NetSample: Equatable {
    var t: Date
    var down: Double
    var up: Double
}

extension NetworkRate {
    static let historyWindow: TimeInterval = 600

    static func appending(_ h: [NetSample], _ s: NetSample) -> [NetSample] {
        (h + [s]).filter { s.t.timeIntervalSince($0.t) <= historyWindow }
    }
}

/// Live speeds, then the sparkline in whatever width they leave (up to 54 pt).
struct NetworkLine: View {
    var down: Double
    var up: Double
    var samples: [NetSample]

    var body: some View {
        HStack(spacing: 6) {
            Text("↓ \(NetworkRate.format(down))  ↑ \(NetworkRate.format(up))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75).layoutPriority(1)
            NetSparkline(samples: samples)
        }
    }
}

/// Download (blue) and upload (orange) of the last 10 minutes, each scaled to the busiest moment.
struct NetSparkline: View {
    var samples: [NetSample]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1, let first = samples.first?.t else { return }
            let peak = max(samples.map { max($0.down, $0.up) }.max() ?? 0, 1_000)
            for (key, color) in [(\NetSample.down, Color.blue), (\NetSample.up, Color.orange)] {
                var p = Path()
                for (i, s) in samples.enumerated() {
                    let x = CGFloat(s.t.timeIntervalSince(first) / NetworkRate.historyWindow) * size.width
                    let y = size.height - CGFloat(s[keyPath: key] / peak) * (size.height - 1) - 0.5
                    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(p, with: .color(color.opacity(0.85)), lineWidth: 1)
            }
        }
        .frame(minWidth: 20, maxWidth: 54, minHeight: 12, maxHeight: 12)
        .accessibilityHidden(true)
    }
}

// MARK: Bluetooth audio connect and disconnect islands

/// Registering touches Bluetooth, which asks for permission: only runs once the user turns the island on.
@MainActor
final class BluetoothIslands: NSObject {
    static let shared = BluetoothIslands()
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    private var since = Date()

    func apply() { UserDefaults.standard.bool(forKey: "bluetoothIsland") ? start() : stop() }

    private func start() {
        guard connectNote == nil else { return }
        since = Date()   // devices already connected are reported right away: no island for them
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    private func stop() {
        connectNote?.unregister(); connectNote = nil
        disconnectNotes.values.forEach { $0.unregister() }; disconnectNotes = [:]
    }

    nonisolated static func symbol(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// "L 85% · R 80% · Case 60%" for `name` out of BluetoothBattery's lines.
    nonisolated static func battery(of name: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(name + ": ") }.map { String($0.dropFirst(name.count + 2)) }
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        MainActor.assumeIsolated {
            guard device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio), let addr = device.addressString else { return }
            disconnectNotes[addr]?.unregister()
            disconnectNotes[addr] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
            guard Date().timeIntervalSince(since) > 3 else { return }
            let name = device.name ?? L("Bluetooth device")
            // AirPods publish their battery a moment after connecting.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                let pct = Self.battery(of: name, in: BluetoothBattery.read())
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        NotchModel.shared.show(Activity(symbol: Self.symbol(for: name), title: name, subtitle: pct ?? L("Connected"), tint: .blue, duration: 4))
                    }
                }
            }
        }
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        MainActor.assumeIsolated {
            note.unregister()
            if let a = device.addressString { disconnectNotes[a] = nil }
            let name = device.name ?? L("Bluetooth device")
            NotchModel.shared.show(Activity(symbol: Self.symbol(for: name), title: name, subtitle: L("Disconnected"), tint: .white, duration: 3))
        }
    }
}
