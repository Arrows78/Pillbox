import AppKit
import SwiftUI
import AVFoundation
import CoreLocation
import EventKit

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, inputMonitoring, screenRecording, fullDisk, calendar, reminders, location, camera, spotify, music
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: L("Accessibility")
        case .inputMonitoring: L("Input Monitoring")
        case .screenRecording: L("Screen Recording")
        case .fullDisk: L("Full Disk Access")
        case .calendar: L("Calendars")
        case .reminders: L("Reminders")
        case .location: L("Location")
        case .camera: L("Camera")
        case .spotify: L("Automation: Spotify")
        case .music: L("Automation: Music")
        }
    }

    var reason: String {
        switch self {
        case .accessibility: L("Keyboard lock, window snapping and paste from the clipboard.")
        case .inputMonitoring: L("Keystroke display and activity counter.")
        case .screenRecording: L("Window watch, Ask about screen, screen recording and QR codes.")
        case .fullDisk: L("Notification mirror and Focus island.")
        case .calendar: L("Next event on Home.")
        case .reminders: L("Reminders tab.")
        case .location: L("Local weather.")
        case .camera: L("Camera mirror.")
        case .spotify: L("Now playing and controls (open Spotify first).")
        case .music: L("Now playing and controls (open Music first).")
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
        case .spotify, .music: "Privacy_Automation"
        }
    }
}

enum PermissionState { case granted, denied, notDetermined, unavailable }

@MainActor
final class PermissionsCenter: ObservableObject {
    static let shared = PermissionsCenter()
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]

    func refresh() { for k in PermissionKind.allCases { states[k] = state(of: k) } }

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
            switch CLLocationManager().authorizationStatus {
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
        case .spotify: return automation(.spotify, ask: false)
        case .music: return automation(.music, ask: false)
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
        case .spotify: _ = automation(.spotify, ask: true)
        case .music: _ = automation(.music, ask: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { self.refresh() } }
    }

    func requestAll() { for k in PermissionKind.allCases where state(of: k) == .notDetermined { request(k) } }

    func openSettings(_ k: PermissionKind) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(k.settingsURL)") { NSWorkspace.shared.open(u) }
    }

    /// Automation consent for another app. Only answerable while that app is running.
    private func automation(_ p: Player, ask: Bool) -> PermissionState {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty else { return .unavailable }
        var desc = AEAddressDesc()
        let id = Array(p.bundleID.utf8)
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
        SettingsCard(title: "Permissions") {
            ForEach(PermissionKind.allCases) { k in
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
        Button("Allow everything that is pending") { center.requestAll() }.controlSize(.small)
            .onAppear { center.refresh() }
            .onReceive(tick) { _ in center.refresh() }
    }
}
