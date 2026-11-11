import CoreGraphics
import XCTest
@testable import Pillbox

final class SnapZoneTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)

    func testLeftHalfTakesTheLeftHalf() {
        XCTAssertEqual(SnapZone.left.frame(in: visible), CGRect(x: 0, y: 0, width: 600, height: 800))
    }

    func testRightThirdTakesTheRightThird() {
        XCTAssertEqual(SnapZone.rightThird.frame(in: visible), CGRect(x: 800, y: 0, width: 400, height: 800))
    }

    func testEveryZoneStaysInsideTheVisibleFrame() {
        for zone in SnapZone.allCases {
            XCTAssertTrue(visible.contains(zone.frame(in: visible)), "\(zone) leaves the visible frame")
        }
    }
}
