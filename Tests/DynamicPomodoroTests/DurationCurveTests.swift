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
        settings.minFocusStartMinutes = 20
        settings.minFocusEndMinutes = 20
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

    private func duration(at hour: Int, _ minute: Int = 0, first: Bool = false) -> Int {
        DurationCurve.focusDuration(
            now: date(hour: hour, minute: minute),
            isFirstSessionOfDay: first,
            settings: settings
        )
    }

    // MARK: - The symmetric bell (both minimums equal)

    @Test func firstSessionOfDayIsAlwaysMinimum() {
        // Even at peak time, first session = min.
        #expect(duration(at: 13, 30, first: true) == 20)
    }

    @Test func midpointReachesMaximum() {
        #expect(duration(at: 13, 30) == 40)
    }

    @Test func workdayEdgesReturnMinimum() {
        #expect(duration(at: 9) == 20)
        #expect(duration(at: 18) == 20)
    }

    @Test func outsideWorkdayClampsToMinimum() {
        #expect(duration(at: 7) == 20)
        #expect(duration(at: 22) == 20)
    }

    @Test func midMorningIsBetweenMinAndMax() {
        let d = duration(at: 10, 30)
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
        #expect(duration(at: 12) == 35)
    }

    @Test func curveIsSymmetricAroundMidpoint() {
        // Mirror across 13:30: 11:30 ↔ 15:30.
        #expect(duration(at: 11, 30) == duration(at: 15, 30))
    }

    // MARK: - Two floors (the end minimum above the start minimum)

    /// The afternoon's floor is its own number. The morning is untouched.
    @Test func endMinimumFloorsTheAfternoonOnly() {
        settings.minFocusEndMinutes = 30
        #expect(duration(at: 9) == 20)
        #expect(duration(at: 18) == 30)
    }

    @Test func outsideTheWorkdayEachSideClampsToItsOwnFloor() {
        settings.minFocusEndMinutes = 30
        #expect(duration(at: 7) == 20)
        #expect(duration(at: 22) == 30)
    }

    /// The warm-up is the start minimum whatever the clock says – a first
    /// session at 17:00 is still the day's first.
    @Test func firstSessionUsesTheStartMinimumEvenLateInTheDay() {
        settings.minFocusEndMinutes = 30
        #expect(duration(at: 17, first: true) == 20)
    }

    /// Both halves share the peak, so there is no step at the midpoint.
    @Test func peakIsSharedByBothHalves() {
        settings.minFocusEndMinutes = 30
        #expect(duration(at: 13, 30) == 40)
        #expect(duration(at: 13, 29) == 40)
    }

    /// Same distance from the peak, different floor: the afternoon session
    /// lands higher than its morning mirror by the difference in floors,
    /// scaled by where on the cosine it sits.
    @Test func afternoonTapersTowardsTheEndMinimum() {
        settings.minFocusEndMinutes = 30
        // 11:30 and 15:30 are both 120 min from the peak: ratio 0.444,
        // weight ≈ 0.587 → morning 20 + 20·0.587 ≈ 32, afternoon 30 + 10·0.587 ≈ 36.
        #expect(duration(at: 11, 30) == 32)
        #expect(duration(at: 15, 30) == 36)
    }

    /// A lower end minimum works the same way in the other direction.
    @Test func endMinimumBelowTheStartMinimumTapersHarder() {
        settings.minFocusEndMinutes = 10
        #expect(duration(at: 9) == 20)
        #expect(duration(at: 18) == 10)
        #expect(duration(at: 15, 30) < duration(at: 11, 30))
    }
}
