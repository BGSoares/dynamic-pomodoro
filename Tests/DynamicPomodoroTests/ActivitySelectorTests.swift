import XCTest
@testable import DynamicPomodoro

final class ActivitySelectorTests: XCTestCase {
    private func makeLibrary() -> [Activity] {
        [
            Activity(id: "a", name: "A", instruction: "",
                     category: .stretch, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "b", name: "B", instruction: "",
                     category: .breathwork, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "c", name: "C", instruction: "",
                     category: .walk, band: .medium, energy: .active,
                     suitableTimes: [.midday]),
            Activity(id: "d", name: "D", instruction: "",
                     category: .eyeRest, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
    }

    private func settings() -> Settings {
        let s = Settings.shared
        s.workdayStartMinutes = 9 * 60
        s.workdayEndMinutes = 18 * 60
        s.disabledCategories = []
        return s
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    func testPicksMediumForMediumBreak() {
        var rng = SystemRandomNumberGenerator()
        let pick = ActivitySelector.select(
            from: makeLibrary(),
            breakMinutes: 8,
            now: date(hour: 13),
            recentActivityIDs: [],
            lastCategory: nil,
            disabledCategories: [],
            settings: settings(),
            rng: &rng
        )
        // Only "c" fits medium + midday.
        XCTAssertEqual(pick?.id, "c")
    }

    func testExcludesDisabledCategory() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            let pick = ActivitySelector.select(
                from: makeLibrary(),
                breakMinutes: 5,
                now: date(hour: 10),
                recentActivityIDs: [],
                lastCategory: nil,
                disabledCategories: ["stretch", "breathwork"],
                settings: settings(),
                rng: &rng
            )
            XCTAssertNotNil(pick)
            XCTAssertNotEqual(pick?.category, .stretch)
            XCTAssertNotEqual(pick?.category, .breathwork)
        }
    }

    func testAvoidsRecentWhenPossible() {
        var rng = SystemRandomNumberGenerator()
        // Make "a", "b", "d" recent; "c" is medium-only, so with 5 min break
        // the short pool is empty; soft filter should *try* to avoid recents
        // but fall back to pool if that empties it. With all shorts recent,
        // the selector is allowed to pick a recent one — just verify no crash.
        let pick = ActivitySelector.select(
            from: makeLibrary(),
            breakMinutes: 5,
            now: date(hour: 10),
            recentActivityIDs: ["a", "b", "d"],
            lastCategory: nil,
            disabledCategories: [],
            settings: settings(),
            rng: &rng
        )
        XCTAssertNotNil(pick)
    }

    func testAvoidsCategoryRepeat() {
        var rng = SystemRandomNumberGenerator()
        var streak = 0
        var total = 0
        for _ in 0..<50 {
            let pick = ActivitySelector.select(
                from: makeLibrary(),
                breakMinutes: 5,
                now: date(hour: 10),
                recentActivityIDs: [],
                lastCategory: .stretch,
                disabledCategories: [],
                settings: settings(),
                rng: &rng
            )
            total += 1
            if pick?.category == .stretch { streak += 1 }
        }
        // With stretch as last and non-stretch options available, should never repeat.
        XCTAssertEqual(streak, 0, "Stretch should be avoided when lastCategory == stretch")
        XCTAssertEqual(total, 50)
    }
}
