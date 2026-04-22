import XCTest
@testable import DynamicPomodoro

final class DurationCurveTests: XCTestCase {
    private func makeSettings() -> Settings {
        let s = Settings.shared
        s.workdayStartMinutes = 9 * 60
        s.workdayEndMinutes = 18 * 60
        s.minFocusMinutes = 20
        s.maxFocusMinutes = 40
        return s
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testFirstSessionOfDayIsAlwaysMinimum() {
        let s = makeSettings()
        // Even at peak time, first session = min.
        let d = DurationCurve.focusDuration(
            now: date(hour: 13, minute: 30),
            isFirstSessionOfDay: true,
            settings: s
        )
        XCTAssertEqual(d, 20)
    }

    func testMidpointReachesMaximum() {
        let s = makeSettings()
        let d = DurationCurve.focusDuration(
            now: date(hour: 13, minute: 30),
            isFirstSessionOfDay: false,
            settings: s
        )
        XCTAssertEqual(d, 40)
    }

    func testWorkdayEdgesReturnMinimum() {
        let s = makeSettings()
        XCTAssertEqual(
            DurationCurve.focusDuration(now: date(hour: 9), isFirstSessionOfDay: false, settings: s),
            20
        )
        XCTAssertEqual(
            DurationCurve.focusDuration(now: date(hour: 18), isFirstSessionOfDay: false, settings: s),
            20
        )
    }

    func testOutsideWorkdayClampsToMinimum() {
        let s = makeSettings()
        let early = DurationCurve.focusDuration(
            now: date(hour: 7), isFirstSessionOfDay: false, settings: s
        )
        let late = DurationCurve.focusDuration(
            now: date(hour: 22), isFirstSessionOfDay: false, settings: s
        )
        XCTAssertEqual(early, 20)
        XCTAssertEqual(late, 20)
    }

    func testMidMorningIsBetweenMinAndMax() {
        let s = makeSettings()
        let d = DurationCurve.focusDuration(
            now: date(hour: 10, minute: 30),
            isFirstSessionOfDay: false,
            settings: s
        )
        XCTAssertGreaterThan(d, 20)
        XCTAssertLessThan(d, 40)
        // Per spec formula: distance=180min, ratio=0.667, cos(π·0.667)≈-0.5,
        // weight=0.25, duration = 20 + 20·0.25 = 25. The spec's illustrative table
        // says "~30 min" here, but the explicit formula block is authoritative.
        XCTAssertEqual(d, 25)
    }

    func testNoonIsBelowPeak() {
        let s = makeSettings()
        // 12:00 is 90min from midpoint → formula yields 35 (not the table's ~40).
        // Confirms we follow the formula, not the table.
        let d = DurationCurve.focusDuration(
            now: date(hour: 12),
            isFirstSessionOfDay: false,
            settings: s
        )
        XCTAssertEqual(d, 35)
    }

    func testCurveIsSymmetricAroundMidpoint() {
        let s = makeSettings()
        let morning = DurationCurve.focusDuration(
            now: date(hour: 11, minute: 30),
            isFirstSessionOfDay: false,
            settings: s
        )
        // Mirror across 13:30 → 15:30.
        let afternoon = DurationCurve.focusDuration(
            now: date(hour: 15, minute: 30),
            isFirstSessionOfDay: false,
            settings: s
        )
        XCTAssertEqual(morning, afternoon)
    }
}
