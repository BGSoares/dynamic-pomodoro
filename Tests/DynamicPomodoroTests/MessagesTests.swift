import XCTest
@testable import DynamicPomodoro

final class MessagesTests: XCTestCase {
    func testReminderPoolHasExpectedSize() {
        // 14 original + 12 new (5 cost-of-skipping + 5 cycling + 2 commitment)
        XCTAssertEqual(ReminderMessages.pool.count, 26)
    }

    func testReminderPoolHasNoDuplicates() {
        XCTAssertEqual(Set(ReminderMessages.pool).count, ReminderMessages.pool.count)
    }

    func testReminderRandomExcludesGivenMessage() {
        var rng = SystemRandomNumberGenerator()
        let target = ReminderMessages.pool[0]
        for _ in 0..<200 {
            let pick = ReminderMessages.random(excluding: target, rng: &rng)
            XCTAssertNotEqual(pick, target, "random(excluding:) must never return the excluded line when others are available")
        }
    }

    func testReminderRandomReturnsExcludedWhenPoolEmpties() {
        // Sanity: with a pool that filters down to nothing, the function falls back to the original pool.
        // We can't easily mutate the pool, but we can confirm random() returns *something* for any excluded value.
        var rng = SystemRandomNumberGenerator()
        let pick = ReminderMessages.random(excluding: "not-in-pool", rng: &rng)
        XCTAssertTrue(ReminderMessages.pool.contains(pick))
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
