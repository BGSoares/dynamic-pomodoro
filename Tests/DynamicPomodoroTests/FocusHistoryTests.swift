import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("FocusHistory")
struct FocusHistoryTests {
    /// Fixed calendar so week boundaries don't depend on the CI runner's
    /// locale: Gregorian, UTC, weeks starting Monday.
    private static func calendar(firstWeekday: Int = 2) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    private let cal = FocusHistoryTests.calendar()

    /// 2025-06-18 is a Wednesday, so the current week runs Mon 16 → Sun 22
    /// June and a four-week window opens on Mon 26 May.
    private func date(_ month: Int, _ day: Int, hour: Int = 10, calendar: Calendar? = nil) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = month; c.day = day; c.hour = hour
        return (calendar ?? cal).date(from: c)!
    }

    private func focus(_ month: Int, _ day: Int, minutes: Int) -> SessionLogEntry {
        let start = date(month, day)
        return SessionLogEntry(
            kind: .focusCompleted,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
            plannedMinutes: minutes,
            activityID: nil
        )
    }

    private func weeks(_ entries: [SessionLogEntry], calendar: Calendar? = nil) -> [FocusWeek] {
        FocusHistory.weeks(from: entries, calendar: calendar ?? cal, now: date(6, 18, hour: 14, calendar: calendar))
    }

    @Test func windowIsFourWholeWeeksEndingWithTodaysWeek() {
        let result = weeks([])
        #expect(result.count == 4)
        #expect(result.allSatisfy { $0.days.count == 7 })
        #expect(result.first?.start == date(5, 26, hour: 0))
        #expect(result.last?.end == date(6, 22, hour: 0))
    }

    @Test func daysAreContiguousAcrossTheWholeWindow() {
        let all = weeks([]).flatMap(\.days)
        #expect(all.count == 28)
        for (earlier, later) in zip(all, all.dropFirst()) {
            #expect(cal.date(byAdding: .day, value: 1, to: earlier.date) == later.date)
        }
    }

    @Test func focusLandsOnItsOwnDay() {
        let result = weeks([focus(6, 10, minutes: 25), focus(6, 10, minutes: 35), focus(6, 12, minutes: 40)])
        let byDate = Dictionary(uniqueKeysWithValues: result.flatMap(\.days).map { ($0.date, $0) })
        #expect(byDate[date(6, 10, hour: 0)]?.focusSeconds == 60 * 60)
        #expect(byDate[date(6, 12, hour: 0)]?.focusSeconds == 40 * 60)
        #expect(byDate[date(6, 11, hour: 0)]?.focusSeconds == 0)
    }

    @Test func daysWithNoSessionsSurviveAsZeros() {
        // A gap is data. Dropping empty days would compress the axis and
        // make a light week look like a busy one.
        let result = weeks([focus(6, 10, minutes: 25)])
        #expect(result.flatMap(\.days).filter { $0.focusSeconds == 0 }.count == 27)
    }

    @Test func perDayTotalsAgreeWithDailyStats() {
        let entries = [
            focus(6, 10, minutes: 25),
            focus(6, 10, minutes: 35),
            SessionLogEntry(kind: .focusAbandoned, startedAt: date(6, 11),
                            endedAt: date(6, 11).addingTimeInterval(9 * 60),
                            plannedMinutes: 30, activityID: nil),
        ]
        for day in weeks(entries).flatMap(\.days) {
            #expect(day.stats == DailyStats.compute(from: entries, calendar: cal, now: day.date))
        }
    }

    @Test func breaksCountAsBreakTimeNotFocus() {
        let day = weeks(dayWithABreak()).flatMap(\.days).first { $0.date == date(6, 10, hour: 0) }
        #expect(day?.focusSeconds == 25 * 60)
        #expect(day?.stats.breakSeconds == 5 * 60)
    }

    // MARK: - Read-outs (the stats window's break-time button)

    /// A day with 25m focus and a 5m break taken, plus a break skipped.
    private func dayWithABreak() -> [SessionLogEntry] {
        let start = date(6, 10)
        return [
            focus(6, 10, minutes: 25),
            SessionLogEntry(kind: .breakCompleted, startedAt: start.addingTimeInterval(25 * 60),
                            endedAt: start.addingTimeInterval(30 * 60),
                            plannedMinutes: 5, activityID: "stairs"),
            SessionLogEntry(kind: .breakSkipped, startedAt: start.addingTimeInterval(60 * 60),
                            endedAt: start.addingTimeInterval(60 * 60 + 20),
                            plannedMinutes: 5, activityID: "stairs"),
        ]
    }

    @Test func breakTimeIsAddedOnlyUnderTheCombinedMeasure() {
        let day = weeks(dayWithABreak()).flatMap(\.days).first { $0.date == date(6, 10, hour: 0) }
        #expect(day?.seconds(.focus) == 25 * 60)
        #expect(day?.seconds(.focusAndBreak) == 30 * 60)
    }

    /// The button adds time the user actually spent on a break — a skipped
    /// break is not desk time, and `DailyStats.contribution` already drops it.
    @Test func skippedBreaksAddNothingUnderEitherMeasure() {
        let withSkipOnly = [
            focus(6, 10, minutes: 25),
            SessionLogEntry(kind: .breakSkipped, startedAt: date(6, 10).addingTimeInterval(25 * 60),
                            endedAt: date(6, 10).addingTimeInterval(25 * 60 + 20),
                            plannedMinutes: 5, activityID: "stairs"),
        ]
        let day = weeks(withSkipOnly).flatMap(\.days).first { $0.date == date(6, 10, hour: 0) }
        #expect(day?.seconds(.focus) == 25 * 60)
        #expect(day?.seconds(.focusAndBreak) == 25 * 60)
    }

    @Test func focusSecondsAgreesWithTheFocusMeasure() {
        for day in weeks(dayWithABreak()).flatMap(\.days) {
            #expect(day.focusSeconds == day.seconds(.focus))
        }
    }

    @Test func weekTotalsSumTheirDaysUnderEitherMeasure() {
        let entries = dayWithABreak() + [focus(6, 12, minutes: 40)]
        // Mon 9 → Sun 15 June is the third week of the window.
        let week = weeks(entries)[2]
        #expect(week.seconds(.focus) == (25 + 40) * 60)
        #expect(week.seconds(.focusAndBreak) == (25 + 5 + 40) * 60)
        #expect(week.focusSeconds == week.seconds(.focus))
    }

    /// Empty days and the unhappened tail of the current week stay at zero
    /// under both read-outs, so turning the button on can't invent a bar.
    @Test func daysWithNothingLoggedStayZeroUnderEitherMeasure() {
        let days = weeks(dayWithABreak()).flatMap(\.days).filter { $0.date != date(6, 10, hour: 0) }
        #expect(days.count == 27)
        #expect(days.allSatisfy { $0.seconds(.focus) == 0 && $0.seconds(.focusAndBreak) == 0 })
    }

    @Test func measuresTitleWhatTheyPlot() {
        #expect(StatsMeasure.focus.title == "Focus per day")
        #expect(StatsMeasure.focusAndBreak.title == "Focus + break per day")
    }

    // MARK: - Window shape

    @Test func daysAfterTodayAreMarkedFuture() {
        let all = weeks([]).flatMap(\.days)
        let future = all.filter(\.isFuture).map(\.date)
        #expect(future == [date(6, 19, hour: 0), date(6, 20, hour: 0),
                           date(6, 21, hour: 0), date(6, 22, hour: 0)])
    }

    @Test func todayIsNotFuture() {
        let today = weeks([]).flatMap(\.days).first { $0.date == date(6, 18, hour: 0) }
        #expect(today?.isFuture == false)
    }

    @Test func sessionsOlderThanTheWindowAreExcluded() {
        // 25 May is the Sunday before the window opens.
        let result = weeks([focus(5, 25, minutes: 50), focus(6, 10, minutes: 25)])
        #expect(result.reduce(0) { $0 + $1.focusSeconds } == 25 * 60)
    }

    @Test func weekTotalSumsItsDays() {
        let result = weeks([focus(6, 9, minutes: 25), focus(6, 11, minutes: 30), focus(6, 15, minutes: 20)])
        // Mon 9 → Sun 15 June is the third week of the window.
        let week = result[2]
        #expect(week.start == date(6, 9, hour: 0))
        #expect(week.focusSeconds == (25 + 30 + 20) * 60)
    }

    @Test func weekBoundariesFollowTheCalendarsFirstWeekday() {
        let sundayFirst = FocusHistoryTests.calendar(firstWeekday: 1)
        let result = weeks([], calendar: sundayFirst)
        // Same instant, Sunday-first weeks: the window opens a day earlier.
        #expect(result.first?.start == date(5, 25, hour: 0, calendar: sundayFirst))
        #expect(result.last?.end == date(6, 21, hour: 0, calendar: sundayFirst))
    }

    @Test func nonPositiveWeekCountYieldsNothing() {
        #expect(FocusHistory.weeks(from: [], weekCount: 0, calendar: cal, now: date(6, 18)).isEmpty)
        #expect(FocusHistory.weeks(from: [], weekCount: -3, calendar: cal, now: date(6, 18)).isEmpty)
    }

    @Test func windowLengthFollowsWeekCount() {
        let result = FocusHistory.weeks(from: [], weekCount: 12, calendar: cal, now: date(6, 18))
        #expect(result.count == 12)
        #expect(result.flatMap(\.days).count == 84)
    }
}
