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
        let status = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Pillbox keep awake" as CFString, &assertion)
        guard status == kIOReturnSuccess else { return }
        active = true
        if let m = minutes {
            until = Date().addingTimeInterval(Double(m) * 60)
            timer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        NotchModel.shared.show(Activity(symbol: "cup.and.saucer.fill", title: L("Keep awake on"),
                                        subtitle: minutes.map { L("for %d min", $0) } ?? L("until turned off"), tint: .orange))
    }

    func stop(silently: Bool = false) {
        guard active else { return }
        IOPMAssertionRelease(assertion); assertion = 0
        timer?.invalidate(); active = false; until = nil
        if !silently { NotchModel.shared.show(Activity(symbol: "cup.and.saucer", title: L("Keep awake off"))) }
    }

    func toggle() { active ? stop() : start() }

    /// Keeps the Mac awake until the next occurrence of a clock time (today, or tomorrow if already past).
    func start(until hour: Int, minute: Int = 0, now: Date = Date()) {
        guard let target = Calendar.current.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) else { return }
        start(minutes: max(Int(target.timeIntervalSince(now) / 60), 1))
    }
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
                                            title: newPlugged ? L("Charging") : L("On battery"), subtitle: "\(newLevel)%",
                                            tint: newPlugged ? .green : .white))
        }
        if newPlugged && newLevel >= target && !notifiedFull {
            notifiedFull = true
            NotchModel.shared.show(Activity(symbol: "battery.100.bolt", title: L("Charged"), subtitle: "\(newLevel)%", tint: .green, duration: 4))
        }
        if !newPlugged || newLevel < target - 2 { notifiedFull = false }
        // Once when the level drops to 10 %, then at each further point lost: never again on every power event.
        if !newPlugged && newLevel <= 10 && (oldLevel > 10 || newLevel < oldLevel) {
            NotchModel.shared.show(Activity(symbol: "battery.0", title: L("Low battery"), subtitle: "\(newLevel)%", tint: .red, duration: 5, priority: .high))
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
        btTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshBluetooth() } }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
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

/// Watches a folder and reports each new entry once (macOS writes screenshots and downloads as temporary files first).
@MainActor
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()
    let dir: URL
    private let onNew: (URL) -> Void
    nonisolated static let temporarySuffixes: Set<String> = ["crdownload", "download", "part", "opdownload", "tmp"]

    init(dir: URL, onNew: @escaping (URL) -> Void) { self.dir = dir; self.onNew = onNew }

    func start() {
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let dispatchSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        dispatchSource.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        dispatchSource.setCancelHandler { close(fd) }
        dispatchSource.resume(); source = dispatchSource
    }

    func stop() { source?.cancel(); source = nil }

    /// Reports entries that appeared since the last call, skipping hidden and temporary files.
    func changed() {
        let now = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        for name in now.subtracting(known).sorted() where !name.hasPrefix(".") && !Self.temporarySuffixes.contains((name as NSString).pathExtension.lowercased()) {
            onNew(dir.appendingPathComponent(name))
        }
        known = now
    }
}

/// Base for a folder watched from launch: `watch(_:)` starts it, and `found` gets each new entry.
@MainActor
class FolderAlertWatcher {
    private var watcher: FolderWatcher?

    func watch(_ dir: URL) {
        watcher = FolderWatcher(dir: dir) { [weak self] url in self?.found(url) }
        watcher?.start()
    }

    func found(_ url: URL) {}
}

@MainActor
final class DownloadsWatcher: FolderAlertWatcher {
    static let shared = DownloadsWatcher()

    func start() {
        watch(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    override func found(_ url: URL) {
        guard Defaults.bool("downloadAlerts", default: true) else { return }
        NotchModel.shared.show(Activity(symbol: "arrow.down.circle.fill", title: L("Download finished"), subtitle: url.lastPathComponent, tint: .blue,
                                        actionTitle: L("Reveal"), action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }, duration: 5))
    }
}

/// New screenshots become an island and are staged on the shelf, ready to drag into any app.
@MainActor
final class ScreenshotWatcher: FolderAlertWatcher {
    static let shared = ScreenshotWatcher()

    static var screenshotFolder: URL {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: (configured as NSString?)?.expandingTildeInPath ?? NSHomeDirectory() + "/Desktop")
    }

    /// macOS tags real screenshots with this extended attribute, whatever the language of the file name.
    static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    func start() {
        watch(Self.screenshotFolder)
    }

    override func found(_ url: URL) {
        // The tag lands a moment after the file appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in MainActor.assumeIsolated { self?.handle(url) } }
    }

    func handle(_ url: URL) {
        guard Defaults.bool("screenshotShelf", default: true), Self.isScreenshot(url) else { return }
        ShelfService.shared.add([url])
        NotchModel.shared.show(Activity(symbol: "camera.viewfinder", title: L("Screenshot ready"), subtitle: L("On the shelf, drag it anywhere"), tint: .green,
                                        actionTitle: L("Copy"), action: {
            if let img = NSImage(contentsOf: url) { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([img]) }
        }, duration: 5))
    }
}

/// Offers a one-tap eject when a removable drive is plugged in.
@MainActor
final class DriveWatcher {
    static let shared = DriveWatcher()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { n in
            guard let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { DriveWatcher.shared.mounted(url) }
        })
    }

    static func isEjectable(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey])
        return (v?.volumeIsEjectable == true || v?.volumeIsRemovable == true) && v?.volumeIsInternal != true
    }

    private func mounted(_ url: URL) {
        guard Defaults.bool("driveEject", default: true), Self.isEjectable(url) else { return }
        NotchModel.shared.show(Activity(symbol: "externaldrive.fill", title: L("Drive connected"), subtitle: url.lastPathComponent, tint: .white,
                                        actionTitle: L("Eject"), action: {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                NotchModel.shared.show(Activity(symbol: "checkmark.circle.fill", title: L("Safe to disconnect"), subtitle: url.lastPathComponent, tint: .green))
            } catch {
                NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle.fill", title: L("Could not eject"), subtitle: url.lastPathComponent, tint: .orange))
            }
        }, duration: 8))
    }
}

@MainActor
enum Tools {
    private static var capsMonitor: Any?
    private static var capsLocalMonitor: Any?
    private static var capsOn = NSEvent.modifierFlags.contains(.capsLock)

    static func startCapsLockHUD() {
        capsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { capsChanged($0) }
        // The global monitor does not see events sent to Pillbox's own windows, so the local one covers those.
        capsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            capsChanged(event)
            return event
        }
    }

    nonisolated private static func capsChanged(_ e: NSEvent) {
        let on = e.modifierFlags.contains(.capsLock)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard on != capsOn else { return }
                capsOn = on
                guard Defaults.bool("capsHUD", default: true) else { return }
                NotchModel.shared.show(Activity(symbol: on ? "capslock.fill" : "capslock", title: on ? L("Caps Lock on") : L("Caps Lock off"),
                                                tint: on ? .yellow : .white, duration: 1.5, priority: .low))
            }
        }
    }

    static func pickColor() {
        NSColorSampler().show { color in
            // The sampler reports on the main thread.
            MainActor.assumeIsolated {
                guard let color else { return }
                let hex = color.hexString
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(hex, forType: .string)
                NotchModel.shared.show(Activity(symbol: "eyedropper.full", title: hex, subtitle: L("Copied"), tint: Color(nsColor: color)))
            }
        }
    }

    /// Interactive area capture straight to the clipboard (system `screencapture`).
    static func captureArea() {
        NotchModel.shared.collapse()
        let screencapture = Process()
        screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-i", "-c"]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Cancelling the capture leaves the clipboard as it was, so a change of its count means a new copy.
            let before = NSPasteboard.general.changeCount
            screencapture.terminationHandler = { _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if NSPasteboard.general.changeCount != before, NSImage(pasteboard: .general) != nil {
                            NotchModel.shared.show(Activity(symbol: "camera.viewfinder", title: L("Screenshot copied"), tint: .green))
                        }
                    }
                }
            }
            do { try screencapture.run() } catch {
                MainActor.assumeIsolated {
                    NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: L("Could not take the screenshot"), tint: .orange))
                }
            }
        }
    }
}

// MARK: Calendar

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    @Published private(set) var next: (title: String, start: Date, end: Date)?
    private let store = EKEventStore()
    private var timer: Timer?
    private var watchdog: Timer?

    /// Asks for access (the Allow buttons), with the system prompt when there is one.
    func start() {
        store.requestFullAccessToEvents { [weak self] ok, _ in
            guard ok else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.begin() } }
        }
    }

    /// Called at launch. It never prompts, and a timer picks up access granted later in System Settings.
    func watch() {
        begin()
        guard timer == nil, watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.begin() }
        }
    }

    /// Starts the refresh once access exists, and only once.
    private func begin() {
        guard timer == nil, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        refresh()
        AgendaModel.shared.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // The refresh timer now runs, so the watchdog has nothing left to do.
        watchdog?.invalidate(); watchdog = nil
    }

    /// Adds a one-hour event (starting at the next full hour when no time was given) to the default calendar.
    func addEvent(title: String, start: Date?) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess, let cal = store.defaultCalendarForNewEvents else {
            NotchModel.shared.show(Activity(symbol: "calendar.badge.exclamationmark", title: L("Calendar access needed"), subtitle: L("Allow it in Settings › Permissions"), tint: .orange)); return
        }
        let event = EKEvent(eventStore: store)
        event.title = title; event.calendar = cal
        event.startDate = start ?? Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date()
        event.endDate = event.startDate.addingTimeInterval(3600)
        do {
            try store.save(event, span: .thisEvent)
            refresh()
            NotchModel.shared.show(Activity(symbol: "calendar.badge.plus", title: L("Event added"), subtitle: title, tint: .green))
        } catch { NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: L("Could not add the event"), tint: .orange)) }
    }

    func refresh() {
        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(86400), calendars: CalendarChoice.visible(in: store))
        let soonest = store.events(matching: pred).filter { !$0.isAllDay && $0.endDate > now }.sorted { $0.startDate < $1.startDate }.first
        next = soonest.map { ($0.title ?? L("Event"), $0.startDate, $0.endDate) }
    }
}
