import Foundation
import XCTest
@testable import Pillbox

/// The launcher search: case-insensitive substring of the name.
final class LauncherFilterTests: XCTestCase {
    func testBlankQueryKeepsEverything() {
        XCTAssertEqual(LauncherFilter.filter(["Safari", "Notes"], query: "") { $0 }, ["Safari", "Notes"])
        XCTAssertEqual(LauncherFilter.filter(["Safari", "Notes"], query: "  ") { $0 }, ["Safari", "Notes"])
    }

    func testMatchesAnywhereInTheNameIgnoringCase() {
        XCTAssertEqual(LauncherFilter.filter(["Safari", "Notes", "Sky"], query: "AF") { $0 }, ["Safari"])
        XCTAssertEqual(LauncherFilter.filter(["Safari", "Notes", "Sky"], query: "s") { $0 }, ["Safari", "Notes", "Sky"])
    }

    func testNoMatchGivesNothing() {
        XCTAssertTrue(LauncherFilter.filter(["Safari"], query: "zzz") { $0 }.isEmpty)
    }
}
