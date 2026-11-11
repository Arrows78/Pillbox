import Foundation
import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import EventKit
import SwiftUI

@MainActor
final class BatteryService: ObservableObject {
    static let shared = BatteryService()
    @Published private(set) var level = 100
    @Published private(set) var charging = false
    @Published private(set) var pluggedIn = false
    private var notifiedFull = false
    private var first = true

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { me.refresh() } }
        }, ctx).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        refresh()
    }

    private func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let description = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { return }
        let newLevel = description[kIOPSCurrentCapacityKey] as? Int ?? level
        let newCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let newPlugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        defer { first = false }
        let wasPlugged = pluggedIn, oldLevel = level
        level = newLevel; charging = newCharging; pluggedIn = newPlugged
        BatteryLog.shared.record(level: newLevel, charging: newCharging, pluggedIn: newPlugged)
        guard !first else { return }

        let target = UserDefaults.standard.integer(forKey: "fullChargeLevel").nonZeroInt ?? 100
        if newPlugged != wasPlugged {
            NotchModel.shared.show(Activity(symbol: newPlugged ? "bolt.fill" : "battery.50",
                                            title: newPlugged ? localized("Charging") : localized("On battery"), subtitle: "\(newLevel)%",
                                            tint: newPlugged ? .green : .white))
        }
        if newPlugged && newLevel >= target && !notifiedFull {
            notifiedFull = true
            NotchModel.shared.show(Activity(symbol: "battery.100.bolt", title: localized("Charged"), subtitle: "\(newLevel)%", tint: .green, duration: 4, kind: .charged))
        }
        if !newPlugged || newLevel < target - 2 { notifiedFull = false }
        // Once when the level drops to 10 %, then at each further point lost: never again on every power event.
        if !newPlugged && newLevel <= 10 && (oldLevel > 10 || newLevel < oldLevel) {
            NotchModel.shared.show(Activity(symbol: "battery.0", title: localized("Low battery"), subtitle: "\(newLevel)%", tint: .red, duration: 5, priority: .high, kind: .lowBattery))
        }
    }
}

extension Int { var nonZeroInt: Int? { self == 0 ? nil : self } }

// MARK: CPU / memory

@MainActor
final class StatsService: ObservableObject {
    static let shared = StatsService()
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var down: Double = 0
    @Published private(set) var up: Double = 0
    @Published private(set) var devices: [DeviceBattery] = []
    @Published private(set) var bluetooth: [String] = []
    @Published private(set) var netHistory: [NetSample] = []
    private var btTimer: Timer?
    private var prevNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevNetDate = Date()
    private var prev: host_cpu_load_info?
    private var devicesScanning = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refreshBluetooth()
        btTimer = PowerGate.timer(every: 60) { [weak self] in MainActor.assumeIsolated { self?.refreshBluetooth() } }
        sample()
        timer = PowerGate.timer(every: 2) { [weak self] in
            MainActor.assumeIsolated { self?.sample() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; btTimer?.invalidate(); btTimer = nil; prev = nil; prevNet = [:] }

    private func refreshBluetooth() {
        DispatchQueue.global(qos: .utility).async {
            let found = BluetoothBattery.read()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.bluetooth = found } }
        }
    }

    /// The IOKit registry walk is slow, so it runs off the main thread every 2 s; one scan at a time.
    private func scanDevices() {
        guard !devicesScanning else { return }
        devicesScanning = true
        DispatchQueue.global(qos: .utility).async {
            let found = DeviceBatteries.scan()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.devices = found; self.devicesScanning = false } }
        }
    }

    private func sample() {
        let net = NetworkRate.counters(), now = Date()
        if !prevNet.isEmpty {
            let rate = NetworkRate.rate(from: prevNet, to: net, seconds: now.timeIntervalSince(prevNetDate)); down = rate.down; up = rate.up
            netHistory = NetworkRate.appending(netHistory, NetSample(t: now, down: rate.down, up: rate.up))
        }
        prevNet = net; prevNetDate = now
        scanDevices()
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if cpuStatus == KERN_SUCCESS, let previous = prev {
            // The tick counters wrap around 2^32: wrapping subtraction gives the right difference across a wrap.
            let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0), system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
            let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2), nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
            let total = user + system + idle + nice
            if total > 0 { cpu = (user + system + nice) / total }
        }
        if cpuStatus == KERN_SUCCESS { prev = info }

        var vm = vm_statistics64(); var vc = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vc)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vc) }
        }
        if vr == KERN_SUCCESS {
            let used = Double(vm.active_count + vm.wire_count + vm.compressor_page_count) * Double(vm_kernel_page_size)
            memory = used / Double(ProcessInfo.processInfo.physicalMemory)
        }
    }
}

// MARK: Downloads, caps lock, eyedropper, screenshots
