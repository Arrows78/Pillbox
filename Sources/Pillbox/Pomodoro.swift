import Foundation

/// The pomodoro cycle: after every few focus sessions, the break is a long one.
enum Pomodoro {
    /// Whether the break after this focus session is the long one. `every` is the number of focus sessions in a cycle;
    /// 0 turns the cycle off.
    static func longBreakDue(focusDone: Int, every: Int) -> Bool {
        every > 0 && focusDone > 0 && focusDone % every == 0
    }
}
