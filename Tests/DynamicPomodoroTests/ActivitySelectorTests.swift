import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("ActivitySelector")
final class ActivitySelectorTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let settings: Settings
    private var rng = SystemRandomNumberGenerator()

    init() {
        suiteName = "ActivitySelectorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = Settings(defaults: defaults)
        settings.workdayStartMinutes = 9 * 60
        settings.workdayEndMinutes = 18 * 60
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeLibrary() -> [Activity] {
        [
            Activity(id: "a", name: "A", instruction: "",
                     category: .stretch, band: .short,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "b", name: "B", instruction: "",
                     category: .breathwork, band: .short,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "c", name: "C", instruction: "",
                     category: .walk, band: .medium,
                     suitableTimes: [.midday]),
            Activity(id: "d", name: "D", instruction: "",
                     category: .eyeRest, band: .short,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    private func select(
        breakMinutes: Int = 5,
        hour: Int = 10,
        recent: [String] = [],
        lastCategory: Activity.Category? = nil,
        from library: [Activity]? = nil
    ) -> Activity? {
        ActivitySelector.select(
            from: library ?? makeLibrary(),
            breakMinutes: breakMinutes,
            now: date(hour: hour),
            recentActivityIDs: recent,
            lastCategory: lastCategory,
            settings: settings,
            rng: &rng
        )
    }

    @Test func picksMediumForMediumBreak() {
        // Only "c" fits medium + midday.
        #expect(select(breakMinutes: 8, hour: 13)?.id == "c")
    }

    @Test func avoidsRecentWhenAlternativeExists() {
        // Shorts at morning are a, b, d. With a and b recent, the soft
        // recency rule must leave only d.
        for _ in 0..<20 {
            #expect(select(recent: ["a", "b"])?.id == "d")
        }
    }

    @Test func recencyRuleRelaxesWhenEverythingIsRecent() {
        // With every candidate recent, the soft rule steps aside and the
        // selector still returns something.
        #expect(select(recent: ["a", "b", "d"]) != nil)
    }

    @Test func avoidsCategoryRepeat() {
        for _ in 0..<50 {
            let pick = select(lastCategory: .stretch)
            #expect(pick?.category != .stretch,
                    "Stretch should be avoided when lastCategory == stretch")
        }
    }

    @Test func returnsNilForEmptyLibrary() {
        #expect(select(from: []) == nil)
    }

    // MARK: - Time-of-day bucketing

    @Test func timeOfDayBucketBoundaries() {
        let start = 9 * 60, end = 18 * 60   // span 540 → 0.25/0.55/0.85 at 135/297/459 min in
        func bucket(_ m: Int) -> Activity.TimeOfDay {
            Activity.TimeOfDay.fromClock(minutesSinceMidnight: m, workdayStart: start, workdayEnd: end)
        }
        #expect(bucket(start) == .morning)               // 09:00, pos 0
        #expect(bucket(start + 134) == .morning)         // just under 0.25
        #expect(bucket(start + 135) == .midday)          // exactly 0.25
        #expect(bucket(start + 296) == .midday)          // just under 0.55
        #expect(bucket(start + 297) == .afternoon)       // exactly 0.55
        #expect(bucket(start + 458) == .afternoon)       // just under 0.85
        #expect(bucket(start + 459) == .endOfDay)        // exactly 0.85
        #expect(bucket(end) == .endOfDay)                // 18:00, pos 1
    }

    @Test func timeOfDayOutsideWorkdayClamps() {
        let start = 9 * 60, end = 18 * 60
        // Before the workday reads as morning; after it as end-of-day.
        #expect(Activity.TimeOfDay.fromClock(minutesSinceMidnight: 6 * 60, workdayStart: start, workdayEnd: end) == .morning)
        #expect(Activity.TimeOfDay.fromClock(minutesSinceMidnight: 22 * 60, workdayStart: start, workdayEnd: end) == .endOfDay)
    }

    // MARK: - Bundled library invariants

    private static let removedIDs: Set<String> = [
        "hip_flexor_stretch",
        "cat_cow",
        "wim_hof_light",
        "legs_up_wall",
    ]

    @Test func bundledLibraryHasNoRemovedIDs() {
        let library = ActivityLibrary.load()
        #expect(!library.isEmpty, "Bundled activities.json should load")
        let ids = Set(library.map { $0.id })
        for removed in Self.removedIDs {
            #expect(!ids.contains(removed),
                    "Removed activity '\(removed)' should not appear in bundled library")
        }
    }

    @Test func bundledLibraryHasInspirationCategory() {
        let library = ActivityLibrary.load()
        #expect(library.contains { $0.category == .inspiration },
                "Bundled library should include at least one inspiration activity")
    }
}
