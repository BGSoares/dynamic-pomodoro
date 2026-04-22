import XCTest
@testable import DynamicPomodoro

final class BreakLogicTests: XCTestCase {
    func testFloorAppliesForShortFocus() {
        XCTAssertEqual(BreakLogic.breakDuration(forFocusMinutes: 20), 5)
        XCTAssertEqual(BreakLogic.breakDuration(forFocusMinutes: 25), 5)
    }

    func testTwentyPercentAppliesAboveFloor() {
        XCTAssertEqual(BreakLogic.breakDuration(forFocusMinutes: 30), 6)
        XCTAssertEqual(BreakLogic.breakDuration(forFocusMinutes: 40), 8)
    }

    func testDurationBandSplits() {
        XCTAssertEqual(BreakLogic.durationBand(forBreakMinutes: 5), .short)
        XCTAssertEqual(BreakLogic.durationBand(forBreakMinutes: 6), .short)
        XCTAssertEqual(BreakLogic.durationBand(forBreakMinutes: 7), .medium)
        XCTAssertEqual(BreakLogic.durationBand(forBreakMinutes: 8), .medium)
    }
}
