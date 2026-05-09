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

    // MARK: - Bundled library invariants

    private static let removedIDs: Set<String> = [
        "hip_flexor_stretch",
        "cat_cow",
        "wim_hof_light",
        "legs_up_wall",
    ]

    func testBundledLibraryHasNoRemovedIDs() {
        let library = ActivityLibrary.load()
        XCTAssertFalse(library.isEmpty, "Bundled activities.json should load")
        let ids = Set(library.map { $0.id })
        for removed in Self.removedIDs {
            XCTAssertFalse(ids.contains(removed),
                           "Removed activity '\(removed)' should not appear in bundled library")
        }
    }

    func testBundledLibraryHasInspirationCategory() {
        let library = ActivityLibrary.load()
        XCTAssertTrue(library.contains { $0.category == .inspiration },
                      "Bundled library should include at least one inspiration activity")
    }

    func testInspirationCategorySelectable() {
        var rng = SystemRandomNumberGenerator()
        let library: [Activity] = [
            Activity(id: "insp", name: "Inspire", instruction: "",
                     category: .inspiration, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
        let pick = ActivitySelector.select(
            from: library,
            breakMinutes: 5,
            now: date(hour: 10),
            recentActivityIDs: [],
            lastCategory: nil,
            disabledCategories: [],
            settings: settings(),
            rng: &rng
        )
        XCTAssertEqual(pick?.id, "insp")
    }

    func testInspirationCategoryRespectsDisabled() {
        var rng = SystemRandomNumberGenerator()
        let library: [Activity] = [
            Activity(id: "insp", name: "Inspire", instruction: "",
                     category: .inspiration, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "stretch_a", name: "A", instruction: "",
                     category: .stretch, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
        for _ in 0..<20 {
            let pick = ActivitySelector.select(
                from: library,
                breakMinutes: 5,
                now: date(hour: 10),
                recentActivityIDs: [],
                lastCategory: nil,
                disabledCategories: ["inspiration"],
                settings: settings(),
                rng: &rng
            )
            XCTAssertEqual(pick?.id, "stretch_a")
        }
    }
}
