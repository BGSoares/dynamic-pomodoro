import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("Messages")
struct MessagesTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    @Test func reminderPoolHasNoDuplicates() {
        #expect(Set(ReminderMessages.pool).count == ReminderMessages.pool.count)
    }

    /// Same calendar day → identical line, regardless of time of day.
    @Test func lineForReturnsSameLineForSameDay() {
        let morning = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: date(2025, 6, 15))!
        let evening = Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: date(2025, 6, 15))!
        #expect(ReminderMessages.lineFor(date: morning) == ReminderMessages.lineFor(date: evening))
    }

    /// The rotation makes consecutive days return different lines (pool is much
    /// larger than 1, so `day % pool.count` advances).
    @Test func lineForAdvancesAcrossConsecutiveDays() {
        let day1 = date(2025, 6, 15)
        let day2 = date(2025, 6, 16)
        #expect(ReminderMessages.lineFor(date: day1) != ReminderMessages.lineFor(date: day2))
    }

    @Test func lineForAlwaysReturnsFromPool() throws {
        for offset in 0..<60 {
            let d = Calendar.current.date(byAdding: .day, value: offset, to: date(2025, 1, 1))!
            let line = try #require(ReminderMessages.lineFor(date: d))
            #expect(ReminderMessages.pool.contains(line))
        }
    }

    @Test func skipNudgePoolNonEmpty() {
        #expect(SkipNudgeMessages.pool.count >= 3)
    }
}
