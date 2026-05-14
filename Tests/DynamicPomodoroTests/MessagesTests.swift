import XCTest
@testable import DynamicPomodoro

final class MessagesTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testReminderPoolHasExpectedSize() {
        XCTAssertEqual(ReminderMessages.pool.count, 26)
    }

    func testReminderPoolHasNoDuplicates() {
        XCTAssertEqual(Set(ReminderMessages.pool).count, ReminderMessages.pool.count)
    }

    /// Same calendar day → identical line, regardless of time of day.
    func testLineForReturnsSameLineForSameDay() {
        let morning = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: date(2025, 6, 15))!
        let evening = Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: date(2025, 6, 15))!
        XCTAssertEqual(
            ReminderMessages.lineFor(date: morning),
            ReminderMessages.lineFor(date: evening)
        )
    }

    /// The rotation makes consecutive days return different lines (pool is much
    /// larger than 1, so `day % pool.count` advances).
    func testLineForAdvancesAcrossConsecutiveDays() {
        let day1 = date(2025, 6, 15)
        let day2 = date(2025, 6, 16)
        XCTAssertNotEqual(
            ReminderMessages.lineFor(date: day1),
            ReminderMessages.lineFor(date: day2)
        )
    }

    func testLineForAlwaysReturnsFromPool() {
        for offset in 0..<60 {
            let d = Calendar.current.date(byAdding: .day, value: offset, to: date(2025, 1, 1))!
            let line = ReminderMessages.lineFor(date: d)
            XCTAssertTrue(ReminderMessages.pool.contains(line))
        }
    }

    func testSkipNudgePoolNonEmpty() {
        XCTAssertGreaterThanOrEqual(SkipNudgeMessages.pool.count, 3)
    }

    func testSkipNudgeRandomReturnsFromPool() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<50 {
            let pick = SkipNudgeMessages.random(rng: &rng)
            XCTAssertTrue(SkipNudgeMessages.pool.contains(pick))
        }
    }
}
