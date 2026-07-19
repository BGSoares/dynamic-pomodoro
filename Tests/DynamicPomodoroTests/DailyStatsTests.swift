import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("DailyStats")
struct DailyStatsTests {
    private let cal = Calendar.current

    private func date(year: Int = 2025, month: Int = 6, day: Int = 15, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute
        return cal.date(from: c)!
    }

    /// `elapsedSeconds` defaults to the full planned span — set it explicitly to
    /// model an abandoned focus that ended before its planned minutes elapsed.
    private func entry(
        _ kind: SessionLogEntry.Kind,
        start: Date,
        plannedMinutes: Int,
        elapsedSeconds: Int? = nil
    ) -> SessionLogEntry {
        let elapsed = elapsedSeconds ?? plannedMinutes * 60
        return SessionLogEntry(
            kind: kind,
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(elapsed)),
            plannedMinutes: plannedMinutes,
            activityID: nil
        )
    }

    @Test func emptyEntriesYieldZeros() {
        let stats = DailyStats.compute(from: [], now: date(hour: 12))
        #expect(stats == .empty)
        #expect(stats.totalSeconds == 0)
    }

    @Test func countsCompletedFocusAsPomos() {
        let now = date(hour: 14)
        let entries = [
            entry(.focusCompleted, start: date(hour: 9), plannedMinutes: 25),
            entry(.focusCompleted, start: date(hour: 11), plannedMinutes: 30),
        ]
        let stats = DailyStats.compute(from: entries, now: now)
        #expect(abs(stats.pomoCount - 2.0) < 0.0001)
        #expect(stats.focusSeconds == (25 + 30) * 60)
        #expect(stats.breakSeconds == 0)
        #expect(stats.totalSeconds == 55 * 60)
    }

    @Test func totalIncludesCompletedBreaks() {
        let now = date(hour: 14)
        let entries = [
            entry(.focusCompleted, start: date(hour: 9), plannedMinutes: 25),
            entry(.breakCompleted, start: date(hour: 9, minute: 25), plannedMinutes: 5),
            entry(.focusCompleted, start: date(hour: 10), plannedMinutes: 30),
            entry(.breakCompleted, start: date(hour: 10, minute: 30), plannedMinutes: 7),
        ]
        let stats = DailyStats.compute(from: entries, now: now)
        #expect(abs(stats.pomoCount - 2.0) < 0.0001)
        #expect(stats.focusSeconds == 55 * 60)
        #expect(stats.breakSeconds == 12 * 60)
        #expect(stats.totalSeconds == 67 * 60)
    }

    @Test func abandonedFocusContributesProportionalPomo() {
        let now = date(hour: 14)
        // 20-min planned, abandoned at minute 10 → 0.5 pomos.
        let entries = [
            entry(.focusAbandoned, start: date(hour: 9), plannedMinutes: 20, elapsedSeconds: 10 * 60),
            entry(.focusCompleted, start: date(hour: 10), plannedMinutes: 25),
        ]
        let stats = DailyStats.compute(from: entries, now: now)
        #expect(abs(stats.pomoCount - 1.5) < 0.0001)
        #expect(stats.focusSeconds == (10 + 25) * 60)
    }

    @Test func abandonedBeyondPlannedCapsAtOnePomo() {
        // Defensive: if elapsed somehow exceeds planned we cap the pomo
        // contribution at 1.0 (no over-credit).
        let entries = [
            entry(.focusAbandoned, start: date(hour: 9), plannedMinutes: 20, elapsedSeconds: 30 * 60),
        ]
        let stats = DailyStats.compute(from: entries, now: date(hour: 14))
        #expect(abs(stats.pomoCount - 1.0) < 0.0001)
    }

    @Test func skippedBreakIsExcluded() {
        let now = date(hour: 14)
        let entries = [
            entry(.focusCompleted, start: date(hour: 9), plannedMinutes: 25),
            entry(.breakSkipped, start: date(hour: 9, minute: 25), plannedMinutes: 5, elapsedSeconds: 30),
        ]
        let stats = DailyStats.compute(from: entries, now: now)
        #expect(abs(stats.pomoCount - 1.0) < 0.0001)
        #expect(stats.focusSeconds == 25 * 60)
        #expect(stats.breakSeconds == 0)
    }

    @Test func entriesFromOtherDaysAreExcluded() {
        let today = date(year: 2025, month: 6, day: 15, hour: 14)
        let yesterday = date(year: 2025, month: 6, day: 14, hour: 14)
        let tomorrow = date(year: 2025, month: 6, day: 16, hour: 9)
        let entries = [
            entry(.focusCompleted, start: yesterday, plannedMinutes: 25),
            entry(.focusCompleted, start: today.addingTimeInterval(-3600), plannedMinutes: 30),
            entry(.focusCompleted, start: tomorrow, plannedMinutes: 25),
        ]
        let stats = DailyStats.compute(from: entries, now: today)
        #expect(abs(stats.pomoCount - 1.0) < 0.0001)
        #expect(stats.focusSeconds == 30 * 60)
    }
}
