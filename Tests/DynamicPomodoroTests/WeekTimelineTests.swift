import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("WeekTimeline")
struct WeekTimelineTests {
    /// Fixed calendar so the tests don't depend on the runner's locale:
    /// Gregorian, UTC, and deliberately Sunday-first – the timeline must
    /// still produce Monday-to-Sunday weeks.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    /// 2025-06-18 is a Wednesday: this week is Mon 16 → Sun 22 June, last
    /// week Mon 9 → Sun 15.
    private func date(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = second
        return cal.date(from: c)!
    }

    private var now: Date { date(6, 18, 14) }

    private func entry(_ kind: SessionLogEntry.Kind, from start: Date, minutes: Int, elapsedSeconds: Int? = nil) -> SessionLogEntry {
        SessionLogEntry(
            kind: kind,
            from: start,
            to: start.addingTimeInterval(TimeInterval(elapsedSeconds ?? minutes * 60)),
            minutes: minutes,
            activity: kind == .breakCompleted || kind == .breakSkipped ? "stairs" : nil
        )
    }

    private func weeks(_ entries: [SessionLogEntry]) -> [TimelineWeek] {
        WeekTimeline.weeks(from: entries, calendar: cal, now: now)
    }

    private func day(_ month: Int, _ day: Int, in entries: [SessionLogEntry]) -> TimelineDay? {
        weeks(entries).flatMap(\.days).first { $0.date == date(month, day, 0) }
    }

    // MARK: - Shape

    @Test func twoWholeWeeksMondayToSundayEndingWithThisWeek() {
        let result = weeks([])
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.days.count == 7 })
        #expect(result.first?.start == date(6, 9, 0))
        #expect(result.first?.end == date(6, 15, 0))
        #expect(result.last?.start == date(6, 16, 0))
        #expect(result.last?.end == date(6, 22, 0))
    }

    @Test func daysAfterTodayAreFutureAndTodayIsNot() {
        let days = weeks([]).flatMap(\.days)
        #expect(days.filter(\.isFuture).map(\.date) == [date(6, 19, 0), date(6, 20, 0), date(6, 21, 0), date(6, 22, 0)])
        #expect(days.first { $0.date == date(6, 18, 0) }?.isFuture == false)
    }

    @Test func emptyWeekKnowsItIsEmpty() {
        let result = weeks([entry(.focusCompleted, from: date(6, 17), minutes: 20)])
        #expect(result[0].isEmpty)
        #expect(!result[1].isEmpty)
    }

    // MARK: - Blocks

    @Test func blocksSitAtTheirWallClockSecondsOnTheirOwnDay() {
        let focus = entry(.focusCompleted, from: date(6, 17, 9, 2), minutes: 20)
        let rest = entry(.breakCompleted, from: date(6, 17, 9, 22), minutes: 5)
        let tuesday = day(6, 17, in: [rest, focus])
        #expect(tuesday?.blocks.map(\.startSecond) == [9 * 3600 + 2 * 60, 9 * 3600 + 22 * 60])
        #expect(tuesday?.blocks.map(\.endSecond) == [9 * 3600 + 22 * 60, 9 * 3600 + 27 * 60])
        #expect(tuesday?.blocks.map(\.kind) == [.focusCompleted, .breakCompleted])
        #expect(day(6, 16, in: [rest, focus])?.blocks.isEmpty == true)
    }

    @Test func abandonedFocusSpansOnlyTheTimeItRan() {
        let abandoned = entry(.focusAbandoned, from: date(6, 17, 10), minutes: 30, elapsedSeconds: 7 * 60 + 15)
        let block = day(6, 17, in: [abandoned])?.blocks.first
        #expect(block?.kind == .focusAbandoned)
        #expect(block?.endSecond == 10 * 3600 + 7 * 60 + 15)
    }

    /// Nothing was taken, so nothing is drawn – the same rule the totals
    /// page applies. The break's start still shows as a gap after the focus.
    @Test func skippedBreaksAreNotDrawn() {
        let focus = entry(.focusCompleted, from: date(6, 17, 9), minutes: 20)
        let skipped = entry(.breakSkipped, from: date(6, 17, 9, 20), minutes: 5, elapsedSeconds: 16)
        #expect(day(6, 17, in: [focus, skipped])?.blocks.map(\.kind) == [.focusCompleted])
    }

    @Test func aSpanPastMidnightIsClippedToItsStartDay() {
        let late = entry(.focusCompleted, from: date(6, 17, 23, 50), minutes: 20)
        let block = day(6, 17, in: [late])?.blocks.first
        #expect(block?.startSecond == 23 * 3600 + 50 * 60)
        #expect(block?.endSecond == 24 * 3600)
        #expect(day(6, 18, in: [late])?.blocks.isEmpty == true)
    }

    @Test func anEntryThatEndsBeforeItStartsIsAPoint() {
        let broken = SessionLogEntry(kind: .focusCompleted, from: date(6, 17, 10), to: date(6, 17, 9), minutes: 20)
        let block = day(6, 17, in: [broken])?.blocks.first
        #expect(block?.startSecond == block?.endSecond)
    }

    @Test func entriesOutsideTheTwoWeeksAreExcluded() {
        let old = entry(.focusCompleted, from: date(6, 8), minutes: 20)   // the Sunday before last week
        let recent = entry(.focusCompleted, from: date(6, 10), minutes: 20)
        let all = weeks([old, recent]).flatMap(\.days).flatMap(\.blocks)
        #expect(all.map(\.entry) == [recent])
    }

    // MARK: - The day's span

    @Test func spanRunsFromFirstStartToLastEnd() {
        let entries = [
            entry(.focusCompleted, from: date(6, 17, 9, 2), minutes: 20),
            entry(.breakCompleted, from: date(6, 17, 9, 22), minutes: 5),
            entry(.focusCompleted, from: date(6, 17, 16, 40), minutes: 25),
        ]
        #expect(day(6, 17, in: entries)?.span == (9 * 3600 + 2 * 60)...(17 * 3600 + 5 * 60))
        #expect(day(6, 16, in: entries)?.span == nil)
    }

    // MARK: - Axis

    @Test func axisIsTheWorkdayWhenNothingIsLogged() {
        let axis = WeekTimeline.axis(covering: weeks([]), workdayStartMinutes: 9 * 60, workdayEndMinutes: 18 * 60)
        #expect(axis == (9 * 60)...(18 * 60))
    }

    @Test func axisWidensToWholeHoursAroundTheEarliestAndLatestLogged() {
        let entries = [
            entry(.focusCompleted, from: date(6, 10, 6, 40), minutes: 20),     // last week, early
            entry(.focusCompleted, from: date(6, 17, 20, 30), minutes: 25),    // this week, late
        ]
        let axis = WeekTimeline.axis(covering: weeks(entries), workdayStartMinutes: 9 * 60, workdayEndMinutes: 18 * 60)
        #expect(axis == (6 * 60)...(21 * 60))
    }

    @Test func axisNeverRunsPastMidnight() {
        let late = entry(.focusCompleted, from: date(6, 17, 23, 50), minutes: 20)
        let axis = WeekTimeline.axis(covering: weeks([late]), workdayStartMinutes: 9 * 60, workdayEndMinutes: 18 * 60)
        #expect(axis.upperBound == 24 * 60)
    }

    @Test func secondsSinceMidnightReadTheWallClock() {
        #expect(TimeFormat.secondsSinceMidnight(from: date(6, 17, 9, 2, second: 30), calendar: cal) == 9 * 3600 + 2 * 60 + 30)
        #expect(TimeFormat.secondsSinceMidnight(from: date(6, 17, 0), calendar: cal) == 0)
        #expect(TimeFormat.minutesSinceMidnight(from: date(6, 17, 9, 2, second: 30), calendar: cal) == 9 * 60 + 2)
    }
}
