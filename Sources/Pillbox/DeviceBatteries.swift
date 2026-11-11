import AppKit
import SwiftUI
import Foundation
import IOKit

struct DeviceBattery: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let percent: Int
}

/// Battery level of Magic Mouse, Magic Keyboard, Trackpad and other HID accessories, from the IOKit registry.
enum DeviceBatteries {
    static func scan() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [String: Int] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Each service is released, and the next one fetched, however the loop body leaves.
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let pct = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
            found[name] = pct
        }
        return found.map { DeviceBattery(name: $0.key, percent: $0.value) }.sorted { $0.name < $1.name }
    }
}

/// Network throughput from interface byte counters (32-bit counters wrap, hence the wrapping subtraction).
enum NetworkRate {
    static func counters() -> [String: (rx: UInt32, tx: UInt32)] {
        var out: [String: (UInt32, UInt32)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return out }
        defer { freeifaddrs(list) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = i.ifa_data, (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            out[String(cString: i.ifa_name)] = (d.ifi_ibytes, d.ifi_obytes)
        }
        return out
    }

    static func rate(from a: [String: (rx: UInt32, tx: UInt32)], to b: [String: (rx: UInt32, tx: UInt32)], seconds: Double) -> (down: Double, up: Double) {
        guard seconds > 0 else { return (0, 0) }
        var rx = 0.0, tx = 0.0
        for (name, now) in b { if let before = a[name] { rx += Double(now.rx &- before.rx); tx += Double(now.tx &- before.tx) } }
        return (rx / seconds, tx / seconds)
    }

    static func format(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bytesPerSecond, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }
}

enum BluetoothBattery {
    /// Connected devices that report a battery, as "Name: L 85% · R 80% · Case 60%".
    static func parse(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = section["device_connected"] as? [[String: Any]] else { return [] }
        let keys: [(String, String)] = [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"), ("device_batteryLevelCase", "Case"), ("device_batteryLevelMain", "")]
        var out: [String] = []
        for entry in connected {
            for (name, info) in entry {
                guard let d = info as? [String: Any] else { continue }
                let parts = keys.compactMap { k, label in (d[k] as? String).map { label.isEmpty ? $0 : "\(label) \($0)" } }
                if !parts.isEmpty { out.append("\(name): " + parts.joined(separator: " · ")) }
            }
        }
        return out.sorted()
    }

    static func read() -> [String] {
        parse(Data(ProcessRunner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]).output.utf8))
    }
}

// MARK: Quick capture from the palette: calendar events and Apple Notes
