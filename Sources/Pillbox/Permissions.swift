import AppKit
import SwiftUI
import AVFoundation
import Combine
import CoreLocation
import EventKit
import Speech
import CoreBluetooth

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, inputMonitoring, screenRecording, fullDisk, calendar, reminders, location, camera, spotify, music, microphone, speech
    case bluetooth, messages, browsers
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: localized("Accessibility")
        case .inputMonitoring: localized("Input Monitoring")
        case .screenRecording: localized("Screen Recording")
        case .fullDisk: localized("Full Disk Access")
        case .calendar: localized("Calendars")
        case .reminders: localized("Reminders")
        case .location: localized("Location")
        case .camera: localized("Camera")
        case .spotify: localized("Automation: Spotify")
        case .music: localized("Automation: Music")
        case .messages: localized("Automation: Messages")
        case .browsers: localized("Automation: browsers")
        case .bluetooth: localized("Bluetooth")
        case .microphone: localized("Microphone")
        case .speech: localized("Speech Recognition")
        }
    }

    var reason: String {
        switch self {
        case .accessibility: localized("Keyboard lock, window snapping and paste from the clipboard.")
        case .inputMonitoring: localized("Keystroke display and activity counter.")
        case .screenRecording: localized("Window watch, Ask about screen, screen recording and QR codes.")
        case .fullDisk: localized("Notification mirror and Focus island.")
        case .calendar: localized("Next event on Home.")
        case .reminders: localized("Reminders tab.")
        case .location: localized("Local weather.")
        case .camera: localized("Camera mirror.")
        case .spotify: localized("Now playing and controls (open Spotify first).")
        case .music: localized("Now playing and controls (open Music first).")
        case .microphone: localized("Dictation and voice following.")
        case .speech: localized("Turns speech into text for dictation and voice following.")
        case .bluetooth: localized("AirPods and headphones connecting, with their battery.")
        case .messages: localized("Replies to messages from the island.")
        case .browsers: localized("Video speed in the front browser tab.")
        }
    }

    /// The card a permission is listed in on the Permissions pane.
    var group: PermissionGroup {
        switch self {
        case .accessibility, .inputMonitoring, .fullDisk: .island
        case .screenRecording, .camera: .capture
        case .microphone, .speech: .voice
        case .calendar, .reminders, .location, .bluetooth: .data
        case .spotify, .music, .messages, .browsers: .automation
        }
    }

    var settingsURL: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .screenRecording: "Privacy_ScreenCapture"
        case .fullDisk: "Privacy_AllFiles"
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .location: "Privacy_LocationServices"
        case .camera: "Privacy_Camera"
        case .spotify, .music, .messages, .browsers: "Privacy_Automation"
        case .bluetooth: "Privacy_Bluetooth"
        case .microphone: "Privacy_Microphone"
        case .speech: "Privacy_SpeechRecognition"
        }
    }
}

/// The cards of the Permissions pane, in order: what each permission is for.
enum PermissionGroup: CaseIterable, Identifiable {
    case island, capture, voice, data, automation
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .island: "Island and keyboard"
        case .capture: "Capture and camera"
        case .voice: "Voice"
        case .data: "Calendar, weather and devices"
        case .automation: "Automation of other apps"
        }
    }
}

enum PermissionState { case granted, denied, notDetermined, unavailable }

@MainActor
final class PermissionsCenter: ObservableObject {
    static let shared = PermissionsCenter()
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]
    private var warnedFeatures: Set<String> = []

    /// Assigns only what changed: a @Published write re-renders the card even when the value is the same.
    func refresh() { for k in PermissionKind.allCases { let s = state(of: k); if states[k] != s { states[k] = s } } }

    /// Global key monitors receive nothing without Input Monitoring, so the feature would look dead. Says so once per feature.
    func checkInputMonitoring(for feature: String) {
        guard !CGPreflightListenEventAccess(), warnedFeatures.insert(feature).inserted else { return }
        NotchModel.shared.show(Activity(symbol: "keyboard.badge.ellipsis", title: localized("%@ needs Input Monitoring", localized(feature)), tint: .orange))
    }

    func state(of k: PermissionKind) -> PermissionState {
        switch k {
        case .accessibility: return AXIsProcessTrusted() ? .granted : .notDetermined
        case .inputMonitoring: return CGPreflightListenEventAccess() ? .granted : .notDetermined
        case .screenRecording: return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .fullDisk:
            let fd = open(FocusMonitor.path, O_RDONLY); if fd >= 0 { close(fd); return .granted }
            return errno == EPERM || errno == EACCES ? .denied : .unavailable
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .reminders:
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .location:
            switch WeatherService.shared.authorizationStatus {
            case .authorizedAlways, .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .spotify: return Self.automation([MusicApp.spotify.bundleID], ask: false)
        case .music: return Self.automation([MusicApp.music.bundleID], ask: false)
        case .messages: return Self.automation(["com.apple.MobileSMS"], ask: false)
        case .browsers: return Self.automation(Array(VideoSpeed.browsers.keys), ask: false)
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    /// Triggers the system prompt when there is one, otherwise sends the user to the right System Settings pane.
    func request(_ k: PermissionKind) {
        let current = state(of: k)
        if current == .denied || (current == .unavailable) { openSettings(k); return }
        switch k {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        case .inputMonitoring: _ = CGRequestListenEventAccess()
        case .calendar: CalendarService.shared.start()
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        case .fullDisk: openSettings(.fullDisk)
        case .reminders: RemindersService.shared.requestAccess()
        case .location: WeatherService.shared.requestAuthorization()
        case .camera: AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .speech: SFSpeechRecognizer.requestAuthorization { _ in }
        case .spotify: askAutomation([MusicApp.spotify.bundleID])
        case .music: askAutomation([MusicApp.music.bundleID])
        case .messages: askAutomation(["com.apple.MobileSMS"])
        case .browsers: askAutomation(Array(VideoSpeed.browsers.keys))
        case .bluetooth: Self.requestBluetooth()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { self.refresh() } }
    }

    func requestAll() { for k in PermissionKind.allCases where state(of: k) == .notDetermined { request(k) } }

    func openSettings(_ k: PermissionKind) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(k.settingsURL)") { NSWorkspace.shared.open(u) }
    }

    /// Asks for Automation consent without blocking the main thread: with `ask`, the system dialog holds the call until it is answered.
    private func askAutomation(_ bundleIDs: [String]) {
        Task.detached {
            _ = Self.automation(bundleIDs, ask: true)
            await MainActor.run { PermissionsCenter.shared.refresh() }
        }
    }

    /// The Bluetooth prompt appears when a central manager is created while the answer is still open. Kept, so it is made once.
    private static var bluetoothPrompt: CBCentralManager?
    private static func requestBluetooth() {
        guard bluetoothPrompt == nil else { return }
        bluetoothPrompt = CBCentralManager(delegate: nil, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    /// Automation consent for other apps. Each answers for itself; only the ones that are running can be asked.
    /// Granted if any is; the first running app is the one asked, the others are only read.
    private nonisolated static func automation(_ bundleIDs: [String], ask: Bool) -> PermissionState {
        let running = bundleIDs.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        guard !running.isEmpty else { return .unavailable }
        let answers = running.enumerated().map { answer(for: $1, ask: ask && $0 == 0) }
        if answers.contains(.granted) { return .granted }
        return answers.allSatisfy { $0 == .denied } ? .denied : .notDetermined
    }

    private nonisolated static func answer(for bundleID: String, ask: Bool) -> PermissionState {
        var desc = AEAddressDesc()
        let id = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), id, id.count, &desc) == noErr else { return .unavailable }
        defer { AEDisposeDesc(&desc) }
        let r = AEDeterminePermissionToAutomateTarget(&desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
        switch r {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notDetermined
        }
    }
}

struct PermissionsCard: View {
    @ObservedObject var center = PermissionsCenter.shared
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ForEach(PermissionGroup.allCases) { group in
            SettingsCard(title: group.title) {
                ForEach(PermissionKind.allCases.filter { $0.group == group }) { k in
                    let st = center.states[k] ?? .notDetermined
                    SettingsRow(title: LocalizedStringKey(k.title), subtitle: LocalizedStringKey(k.reason)) {
                        HStack(spacing: 8) {
                            Image(systemName: st == .granted ? "checkmark.circle.fill" : st == .denied ? "xmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(st == .granted ? Color.green : st == .denied ? Color.red : Color.secondary)
                            if st != .granted {
                                Button(LocalizedStringKey(st == .denied || st == .unavailable ? "Open Settings" : "Allow")) { center.request(k) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        Button("Allow everything that is pending") { center.requestAll() }.controlSize(.small)
            .onAppear { center.refresh() }
            .onReceive(tick) { _ in center.refresh() }
    }
}
