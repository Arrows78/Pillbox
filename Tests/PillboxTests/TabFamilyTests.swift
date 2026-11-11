import XCTest
@testable import Pillbox

/// Tab families and the hairlines the bar draws between them.
final class TabFamilyTests: XCTestCase {
    func testEveryTabHasAFamilyAndEveryFamilyIsUsed() {
        let used = Set(Tab.allCases.map(\.family))
        XCTAssertEqual(used, [.daily, .work, .tools])
    }

    func testSeparatorsOnlyWhereNeighboursDiffer() {
        XCTAssertEqual(TabBarMetrics.separators(in: [.home, .music, .timer]), 0)
        XCTAssertEqual(TabBarMetrics.separators(in: [.home, .stocks, .launcher]), 2)
        XCTAssertEqual(TabBarMetrics.separators(in: [.home, .stocks, .music]), 2)
        XCTAssertEqual(TabBarMetrics.separators(in: [.home]), 0)
        XCTAssertEqual(TabBarMetrics.separators(in: []), 0)
    }

    func testTheBarNeverOverflowsWithSeparators() {
        let bar = NotchModel.expandedSize.width - 44 - 10 - 26 - 10 - 20
        // A scattered order makes the most hairlines.
        let scattered: [Tab] = [.home, .stocks, .music, .launcher, .timer, .ai, .terminal, .calendar, .pulls, .prompter, .reminders, .clipboard, .notifications, .shelf, .notes]
        for sel in Tab.allCases {
            let s = TabBarMetrics.split(scattered, selected: sel, available: bar)
            let w = TabBarMetrics.rowWidth(s.shown, selected: sel) + (s.more.isEmpty ? 0 : TabBarMetrics.spacing + TabBarMetrics.more)
            XCTAssertLessThanOrEqual(w, bar)
            XCTAssertTrue(s.shown.contains(sel))
            XCTAssertEqual(s.shown.count + s.more.count, scattered.count)
        }
    }
}
