import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("DurationCurve")
final class DurationCurveTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let settings: Settings

    init() {
        suiteName = "DurationCurveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = Settings(defaults: defaults)
        settings.workdayStartMinutes = 9 * 60
        settings.workdayEndMinutes = 18 * 60
        settings.minFocusMinutes = 20
        settings.maxFocusMinutes = 40
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    @Test func firstSessionOfDayIsAlwaysMinimum() {
        // Even at peak time, first session = min.
        let d = DurationCurve.focusDuration(
            now: date(hour: 13, minute: 30),
            isFirstSessionOfDay: true,
            settings: settings
        )
        #expect(d == 20)
    }

    @Test func midpointReachesMaximum() {
        let d = DurationCurve.focusDuration(
            now: date(hour: 13, minute: 30),
            isFirstSessionOfDay: false,
            settings: settings
        )
        #expect(d == 40)
    }

    @Test func workdayEdgesReturnMinimum() {
        #expect(DurationCurve.focusDuration(now: date(hour: 9), isFirstSessionOfDay: false, settings: settings) == 20)
        #expect(DurationCurve.focusDuration(now: date(hour: 18), isFirstSessionOfDay: false, settings: settings) == 20)
    }

    @Test func outsideWorkdayClampsToMinimum() {
        let early = DurationCurve.focusDuration(
            now: date(hour: 7), isFirstSessionOfDay: false, settings: settings
        )
        let late = DurationCurve.focusDuration(
            now: date(hour: 22), isFirstSessionOfDay: false, settings: settings
        )
        #expect(early == 20)
        #expect(late == 20)
    }

    @Test func midMorningIsBetweenMinAndMax() {
        let d = DurationCurve.focusDuration(
            now: date(hour: 10, minute: 30),
            isFirstSessionOfDay: false,
            settings: settings
        )
        #expect(d > 20)
        #expect(d < 40)
        // Per spec formula: distance=180min, ratio=0.667, cos(π·0.667)≈-0.5,
        // weight=0.25, duration = 20 + 20·0.25 = 25. The spec's illustrative table
        // says "~30 min" here, but the explicit formula block is authoritative.
        #expect(d == 25)
    }

    @Test func noonIsBelowPeak() {
        // 12:00 is 90min from midpoint → formula yields 35 (not the table's ~40).
        // Confirms we follow the formula, not the table.
        let d = DurationCurve.focusDuration(
            now: date(hour: 12),
            isFirstSessionOfDay: false,
            settings: settings
        )
        #expect(d == 35)
    }

    @Test func curveIsSymmetricAroundMidpoint() {
        let morning = DurationCurve.focusDuration(
            now: date(hour: 11, minute: 30),
            isFirstSessionOfDay: false,
            settings: settings
        )
        // Mirror across 13:30 → 15:30.
        let afternoon = DurationCurve.focusDuration(
            now: date(hour: 15, minute: 30),
            isFirstSessionOfDay: false,
            settings: settings
        )
        #expect(morning == afternoon)
    }
}
