import Foundation

/// Apps whose notifications no longer raise an island. Their notifications still reach Notification Center and the
/// list in the Notifications tab, and verification codes still show: a code is what the user needs at once.
enum NotificationMute {
    static let key = "mutedNotificationApps"

    static var apps: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func isMuted(_ app: String) -> Bool { apps.contains(app) }

    static func setMuted(_ app: String, _ muted: Bool) {
        var set = apps
        if muted { set.insert(app) } else { set.remove(app) }
        UserDefaults.standard.set(set.sorted(), forKey: key)
    }
}
