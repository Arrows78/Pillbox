import Foundation

extension SelfTest {
    /// The Alerts table: each kind has its own keys, the table's settings reach the island when it is shown, and an
    /// island the user never changed keeps the priority and duration it had before the table existed.
    static func islandTable() {
        let kinds = IslandKind.allCases
        let keys = kinds.flatMap { [Preferences.islandOn($0).key, Preferences.islandPriority($0).key, Preferences.islandDuration($0).key] }
        check("island table: every kind has its own preference keys", Set(keys).count == keys.count)
        check("island table: priority names round-trip", Activity.Priority.all.allSatisfy { Activity.Priority(key: $0.key) == $0 } && Activity.Priority(key: "bogus") == nil)

        func clear() { for key in keys { UserDefaults.standard.removeObject(forKey: key) } }
        clear(); defer { clear() }

        let untouched = NotchModel()
        untouched.show(Activity(symbol: "capslock", title: "Caps Lock on", tint: .yellow, duration: 1.5, priority: .low, kind: .capsLock))
        check("island table: a kind the table never wrote keeps its own duration", untouched.activity?.title == "Caps Lock on" && untouched.activity?.duration == 1.5)
        check("island table: and its own priority", IslandKind.capsLock.applied(to: Activity(symbol: "x", title: "y", priority: .low, kind: .capsLock))?.priority == .low)

        UserDefaults.standard.set(false, forKey: Preferences.islandOn(.notification).key)
        let off = NotchModel()
        off.show(Activity(symbol: "bell.fill", title: "Mail", kind: .notification))
        check("island table: a turned-off kind is dropped", off.activity == nil)
        let untagged = NotchModel()
        untagged.show(Activity(symbol: "bell.fill", title: "Untagged", kind: nil))
        check("island table: an island without a kind is not affected", untagged.activity?.title == "Untagged")
        UserDefaults.standard.removeObject(forKey: Preferences.islandOn(.notification).key)

        UserDefaults.standard.set(Activity.Priority.high.key, forKey: Preferences.islandPriority(.download).key)
        UserDefaults.standard.set(7.0, forKey: Preferences.islandDuration(.download).key)
        let changed = NotchModel()
        changed.show(Activity(symbol: "arrow.down.circle.fill", title: "Download finished", duration: 5, kind: .download))
        check("island table: a set priority and duration reach the island", changed.activity?.duration == 7 && changed.activity?.priority == .high)
        check("island table: a set priority applies to the kind alone", IslandKind.focus.applied(to: Activity(symbol: "moon", title: "Focus", duration: 2.5, kind: .focus))?.duration == 2.5)
    }
}
