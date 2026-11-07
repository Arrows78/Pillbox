import AppKit
import IOKit.pwr_mgt
import IOKit.ps
import EventKit
import SwiftUI

// MARK: Keep awake

@MainActor
final class CaffeineService: ObservableObject {
    static let shared = CaffeineService()
    @Published private(set) var active = false
    @Published private(set) var until: Date?
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?

    /// `minutes == nil` keeps the Mac awake until turned off.
    func start(minutes: Int? = nil) {
        stop(silently: true)
        let r = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Pillbox keep awake" as CFString, &assertion)
        guard r == kIOReturnSuccess else { return }
        active = true
        if let m = minutes {
            until = Date().addingTimeInterval(Double(m) * 60)
            timer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        NotchModel.shared.show(Activity(symbol: "cup.and.saucer.fill", title: "Keep awake on",
                                        subtitle: minutes.map { "for \($0) min" } ?? "until turned off", tint: .orange))
    }

    func stop(silently: Bool = false) {
        guard active else { return }
        IOPMAssertionRelease(assertion); assertion = 0
        timer?.invalidate(); active = false; until = nil
        if !silently { NotchModel.shared.show(Activity(symbol: "cup.and.saucer", title: "Keep awake off")) }
    }

    func toggle() { active ? stop() : start() }
}

// MARK: Battery

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
              let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { return }
        let newLevel = d[kIOPSCurrentCapacityKey] as? Int ?? level
        let newCharging = d[kIOPSIsChargingKey] as? Bool ?? false
        let newPlugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        defer { first = false }
        let wasPlugged = pluggedIn
        level = newLevel; charging = newCharging; pluggedIn = newPlugged
        guard !first else { return }

        let target = UserDefaults.standard.integer(forKey: "fullChargeLevel").nonZeroInt ?? 100
        if newPlugged != wasPlugged {
            NotchModel.shared.show(Activity(symbol: newPlugged ? "bolt.fill" : "battery.50",
                                            title: newPlugged ? "Charging" : "On battery", subtitle: "\(newLevel)%",
                                            tint: newPlugged ? .green : .white))
        }
        if newPlugged && newLevel >= target && !notifiedFull {
            notifiedFull = true
            NotchModel.shared.show(Activity(symbol: "battery.100.bolt", title: "Charged", subtitle: "\(newLevel)%", tint: .green, duration: 4))
        }
        if !newPlugged || newLevel < target - 2 { notifiedFull = false }
        if !newPlugged && newLevel <= 10 && newLevel < level + 1 {
            NotchModel.shared.show(Activity(symbol: "battery.0", title: "Low battery", subtitle: "\(newLevel)%", tint: .red, duration: 5))
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
    private var prev: host_cpu_load_info?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; prev = nil }

    private func sample() {
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if r == KERN_SUCCESS, let p = prev {
            let u = Double(info.cpu_ticks.0 - p.cpu_ticks.0), s = Double(info.cpu_ticks.1 - p.cpu_ticks.1)
            let i = Double(info.cpu_ticks.2 - p.cpu_ticks.2), n = Double(info.cpu_ticks.3 - p.cpu_ticks.3)
            let total = u + s + i + n
            if total > 0 { cpu = (u + s + n) / total }
        }
        if r == KERN_SUCCESS { prev = info }

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

@MainActor
final class DownloadsWatcher {
    static let shared = DownloadsWatcher()
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    private let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    func start() {
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        s.setCancelHandler { close(fd) }
        s.resume(); source = s
    }

    private func changed() {
        let temp = ["crdownload", "download", "part", "opdownload", "tmp"]
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        for name in now.subtracting(known) where !name.hasPrefix(".") && !temp.contains((name as NSString).pathExtension.lowercased()) {
            let url = dir.appendingPathComponent(name)
            guard UserDefaults.standard.object(forKey: "downloadAlerts") as? Bool ?? true else { continue }
            NotchModel.shared.show(Activity(symbol: "arrow.down.circle.fill", title: "Download finished", subtitle: name, tint: .blue,
                                            actionTitle: "Reveal", action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }, duration: 5))
        }
        known = now
    }
}

@MainActor
enum Tools {
    private static var capsMonitor: Any?
    private static var capsOn = NSEvent.modifierFlags.contains(.capsLock)

    static func startCapsLockHUD() {
        capsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { e in
            let on = e.modifierFlags.contains(.capsLock)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard on != capsOn else { return }
                    capsOn = on
                    guard UserDefaults.standard.object(forKey: "capsHUD") as? Bool ?? true else { return }
                    NotchModel.shared.show(Activity(symbol: on ? "capslock.fill" : "capslock", title: on ? "Caps Lock on" : "Caps Lock off",
                                                    tint: on ? .yellow : .white, duration: 1.5))
                }
            }
        }
    }

    static func pickColor() {
        NSColorSampler().show { color in
            guard let color else { return }
            let hex = color.hexString
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
            NotchModel.shared.show(Activity(symbol: "eyedropper.full", title: hex, subtitle: "Copied", tint: Color(nsColor: color)))
        }
    }

    /// Interactive area capture straight to the clipboard (system `screencapture`).
    static func captureArea() {
        NotchModel.shared.collapse()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-c"]
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if NSImage(pasteboard: .general) != nil {
                        NotchModel.shared.show(Activity(symbol: "camera.viewfinder", title: "Screenshot copied", tint: .green))
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { try? p.run() }
    }
}

// MARK: Calendar

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var next: (title: String, start: Date, end: Date)?
    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                        MainActor.assumeIsolated { self?.refresh() }
                    }
                }
            }
        }
    }

    func refresh() {
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(86400), calendars: nil)
        let e = store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.first
        next = e.map { ($0.title ?? "Event", $0.startDate, $0.endDate) }
    }
}
