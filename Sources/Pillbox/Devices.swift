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
        while case let svc = IOIteratorNext(iterator), svc != 0 {
            defer { IOObjectRelease(svc) }
            guard let pct = IORegistryEntryCreateCFProperty(svc, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(svc, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
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
        for (k, new) in b { if let old = a[k] { rx += Double(new.rx &- old.rx); tx += Double(new.tx &- old.tx) } }
        return (rx / seconds, tx / seconds)
    }

    static func format(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bytesPerSecond, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? String(format: "%.0f %@", v, units[i]) : String(format: "%.1f %@", v, units[i])
    }
}
