import Foundation
import SwiftUI

/// The kinds of island that Settings > Alerts lists in its table: each can be turned off, and its priority and duration
/// changed. An island is tagged with its kind (`Activity.kind`) where it is shown; `NotchModel.show` applies the table.
/// The defaults are the values the island has at its call site, so nothing changes until the table is edited.
enum IslandKind: String, CaseIterable, Identifiable {
    case capsLock, volume, brightness, focus, call, build, download, drive, bluetooth, screenshot, notification, verificationCode, charged, lowBattery
    var id: String { rawValue }
    /// The stored name of the kind: part of the preference keys, so it must never change.
    var key: String { rawValue }

    /// The name the table row shows.
    var title: LocalizedStringKey {
        switch self {
        case .capsLock: "Caps Lock"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .focus: "Focus"
        case .call: "Call in progress"
        case .build: "Build finished"
        case .download: "Download finished"
        case .drive: "Drive connected"
        case .bluetooth: "Bluetooth audio"
        case .screenshot: "Screenshot ready"
        case .notification: "New notification"
        case .verificationCode: "Verification code"
        case .charged: "Charged"
        case .lowBattery: "Low battery"
        }
    }

    var defaultPriority: Activity.Priority {
        switch self {
        case .capsLock, .volume, .brightness: .low
        case .call, .lowBattery: .high
        default: .normal
        }
    }

    /// Seconds on screen. Bluetooth disconnects stay 3 s by default, the connection shows 4 s.
    var defaultDuration: Double {
        switch self {
        case .capsLock: 1.5
        case .volume, .brightness: 1.4
        case .focus: 2.5
        case .call: 3
        case .drive: 8
        case .build, .bluetooth, .charged: 4
        case .download, .screenshot, .notification, .lowBattery: 5
        case .verificationCode: 12
        }
    }

    /// The activity with the table's settings applied, or nil when this kind is turned off. A priority or duration the
    /// user never set keeps the value the island was given where it was shown.
    func applied(to activity: Activity) -> Activity? {
        guard Preferences.islandOn(self).value else { return nil }
        var result = activity
        let priority = Preferences.islandPriority(self)
        if Self.isSet(priority.key), let p = Activity.Priority(key: priority.value) { result.priority = p }
        let duration = Preferences.islandDuration(self)
        if Self.isSet(duration.key) { result.duration = duration.value }
        return result
    }

    /// True once the table has written this setting, so a default is never stored as an override.
    private static func isSet(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) != nil }
}

extension Activity.Priority {
    static let all: [Activity.Priority] = [.low, .normal, .high]

    /// The stored name of the priority.
    var key: String {
        switch self {
        case .low: "low"
        case .normal: "normal"
        case .high: "high"
        }
    }

    init?(key: String) {
        guard let p = Self.all.first(where: { $0.key == key }) else { return nil }
        self = p
    }

    var title: String {
        switch self {
        case .low: localized("Low")
        case .normal: localized("Normal")
        case .high: localized("High")
        }
    }
}
