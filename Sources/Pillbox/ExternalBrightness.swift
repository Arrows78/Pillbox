import AppKit
import IOKit

// MARK: External display brightness over DDC/CI (Apple silicon)

/// Sets the brightness of external monitors by writing the DDC/CI "set VCP feature" command (code 0x10) to the
/// display services the system exposes. Apple silicon only; a Mac with no external display does nothing.
@MainActor
enum ExternalBrightness {
    static let key = "externalBrightness"
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias Write = @convention(c) (AnyObject, UInt32, UInt32, UnsafeRawPointer, UInt32) -> Int32
    private static let handle = dlopen(nil, RTLD_LAZY)
    private static let create = handle.flatMap { dlsym($0, "IOAVServiceCreateWithService") }.map { unsafeBitCast($0, to: Create.self) }
    private static let write = handle.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: Write.self) }

    /// The DDC/CI packet that sets VCP 0x10 (brightness) to `percent`, checksum included.
    /// The host sends from 0x51 to the monitor at 0x6E; the checksum covers both addresses and every byte after them.
    nonisolated static func packet(percent: Int) -> [UInt8] {
        let v = UInt8(clamping: min(max(percent, 0), 100))
        let body: [UInt8] = [0x84, 0x03, 0x10, 0x00, v]
        let checksum = body.reduce(UInt8(0x6E) ^ UInt8(0x51)) { $0 ^ $1 }
        return body + [checksum]
    }

    /// What a brightness write found: a display took the command, displays were found but rejected it, or there were none.
    enum WriteResult { case written, rejected, noDisplay }

    /// Writes the brightness to every external display.
    static func set(_ percent: Int) -> WriteResult {
        guard let create, let write else { return .noDisplay }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else { return .noDisplay }
        defer { IOObjectRelease(iterator) }
        var found = false, wrote = false
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard location == "External", let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
            found = true
            var data = packet(percent: percent)
            // Monitors drop a command sent too soon after the last one: DDC/CI asks for a short pause between them.
            for _ in 0..<2 {
                usleep(10_000)
                if write(service, 0x37, 0x51, &data, UInt32(data.count)) == 0 { wrote = true }
            }
        }
        return wrote ? .written : (found ? .rejected : .noDisplay)
    }

    /// Moves the stored level by `delta` percent and writes it to the external displays, showing it on the island.
    /// The new level is stored only when a display accepted it.
    static func step(_ delta: Int) {
        let now = UserDefaults.standard.object(forKey: key) as? Int ?? 50
        let v = min(max(now + delta, 0), 100)
        switch set(v) {
        case .written:
            UserDefaults.standard.set(v, forKey: key)
            NotchModel.shared.show(Activity(symbol: "sun.max.fill", title: L("External display brightness"), tint: .yellow, progress: Double(v) / 100, duration: 1.4))
        case .rejected:
            NotchModel.shared.show(Activity(symbol: "display", title: L("External display did not respond"), duration: 2))
        case .noDisplay:
            NotchModel.shared.show(Activity(symbol: "display", title: L("No external display found"), duration: 2))
        }
    }
}
