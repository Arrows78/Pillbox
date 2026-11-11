import Foundation

/// The quiet period: between two hours, the islands that are not urgent wait instead of showing. An urgent island
/// (priority high: a low battery, a call, a verification code) still shows.
enum QuietHours {
    /// Whether `hour` falls in the period from `from` to `to`, which may cross midnight. Off when `from` is -1 or the
    /// two hours are the same.
    static func isQuiet(hour: Int, from: Int, to: Int) -> Bool {
        guard from >= 0, to >= 0, from != to else { return false }
        return from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }

    @MainActor static func isNow(_ date: Date = Date()) -> Bool {
        isQuiet(hour: Calendar.current.component(.hour, from: date), from: Preferences.quietFrom.value, to: Preferences.quietTo.value)
    }

    /// Whether an island should wait now: not urgent, and inside the quiet period.
    @MainActor static func holds(_ activity: Activity, now: Date = Date()) -> Bool {
        activity.priority != .high && isNow(now)
    }
}
