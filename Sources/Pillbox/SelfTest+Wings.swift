import Foundation

extension SelfTest {
    /// The wings of the pill: which item takes each wing, by priority, one per side, and the settings that name them.
    static func pillWings() {
        func slot(_ item: WingItem, _ side: WingSide, _ priority: Int, live: Bool = true) -> WingSlot {
            WingSlot(item: item, side: side, priority: priority, live: live)
        }
        let none = WingLayout.choose([])
        check("wings: nothing live means empty wings", none.left == nil && none.right == nil)

        let alertOverTimer = WingLayout.choose([slot(.timer, .left, 65), slot(.recording, .left, 100)])
        check("wings: the higher priority live item takes the wing", alertOverTimer.left == .recording)

        let skipsDead = WingLayout.choose([slot(.recording, .left, 100, live: false), slot(.timer, .left, 65)])
        check("wings: a slot that is not live is skipped", skipsDead.left == .timer)

        let sides = WingLayout.choose([slot(.timer, .right, 65)])
        check("wings: a right slot never fills the left wing", sides.left == nil && sides.right == .timer)

        let many = WingLayout.choose([slot(.recording, .left, 100), slot(.call, .left, 90), slot(.build, .left, 85),
                                      slot(.timer, .right, 65), slot(.track, .right, 60), slot(.stocks, .right, 57)])
        let shown = [many.left, many.right].compactMap { $0 }
        check("wings: at most two items, the highest priority on each side", shown == [.recording, .timer], "\(shown)")

        let rank = WingLayout.userRank
        let userVsAlert = WingLayout.choose([slot(.clock, .left, rank), slot(.recording, .left, 100)])
        check("wings: an alert outranks the user's choice", userVsAlert.left == .recording)
        let userVsTimer = WingLayout.choose([slot(.timer, .left, 65), slot(.clock, .left, rank)])
        check("wings: the user's choice outranks the timer on its wing", userVsTimer.left == .clock)

        let builtInTimer = WingLayout.builtIn.filter { $0.item == .timer }.map(\.priority)
        check("wings: the user's choice ranks between the alerts and the timer",
              WingLayout.builtIn.filter { $0.item == .recording }.allSatisfy { $0.priority > rank } && builtInTimer.allSatisfy { $0 < rank })
        check("wings: built-in slots are unique per item and side",
              Set(WingLayout.builtIn.map { "\($0.item.rawValue)-\($0.side)" }).count == WingLayout.builtIn.count)

        check("wings: none and unknown settings choose nothing",
              WingItem.configured("none") == nil && WingItem.configured("bogus") == nil && WingItem.configured("") == nil)
        check("wings: each choice is a setting value, and none comes first",
              WingItem.choices.allSatisfy { WingItem.settingValues.contains($0.rawValue) } && WingItem.settingValues.first == "none")
        check("wings: every choice has its own title", Set(WingItem.choices.map(\.title)).count == WingItem.choices.count)
        check("wings: resting pill keeps battery and clock by default",
              Preferences.restingLeft.defaultValue == "battery" && Preferences.restingRight.defaultValue == "clock")
        check("wings: the live wings are empty by default", Preferences.wingLeft.defaultValue == "none" && Preferences.wingRight.defaultValue == "none")
    }
}
