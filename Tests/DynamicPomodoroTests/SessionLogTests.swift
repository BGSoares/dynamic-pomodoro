import XCTest
@testable import DynamicPomodoro

final class SessionLogTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }

    private func entry(kind: SessionLogEntry.Kind, on day: Date) -> SessionLogEntry {
        SessionLogEntry(
            kind: kind,
            startedAt: day,
            endedAt: day.addingTimeInterval(300),
            plannedMinutes: 5,
            activityID: nil
        )
    }

    func testCountsCompletedAndSkippedBreaksToday() {
        let today = date(2025, 6, 15)
        let entries: [SessionLogEntry] = [
            entry(kind: .breakCompleted, on: today),
            entry(kind: .breakSkipped, on: today),
            entry(kind: .breakCompleted, on: today),
        ]
        XCTAssertEqual(SessionLogStore.breakCountToday(in: entries, now: today), 3)
    }

    func testIgnoresFocusEntries() {
        let today = date(2025, 6, 15)
        let entries: [SessionLogEntry] = [
            entry(kind: .focusCompleted, on: today),
            entry(kind: .focusAbandoned, on: today),
            entry(kind: .breakCompleted, on: today),
        ]
        XCTAssertEqual(SessionLogStore.breakCountToday(in: entries, now: today), 1)
    }

    func testIgnoresOtherDays() {
        let yesterday = date(2025, 6, 14)
        let today = date(2025, 6, 15)
        let entries: [SessionLogEntry] = [
            entry(kind: .breakCompleted, on: yesterday),
            entry(kind: .breakCompleted, on: yesterday),
            entry(kind: .breakCompleted, on: today),
        ]
        XCTAssertEqual(SessionLogStore.breakCountToday(in: entries, now: today), 1)
    }

    func testEmptyLogReturnsZero() {
        let today = date(2025, 6, 15)
        XCTAssertEqual(SessionLogStore.breakCountToday(in: [], now: today), 0)
    }
}
