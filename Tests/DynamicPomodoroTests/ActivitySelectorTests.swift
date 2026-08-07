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

    /// Every soft rule in `select` is a deliberate no-op when it would empty the pool, so a
    /// thin cell disables the very rules meant to keep breaks distinct. Six is the floor at
    /// which `prefix(3)` recency still leaves a real choice; three categories is what stops
    /// the category rule from being structurally dead. Shipped at 1 activity for
    /// medium/morning and 0 for medium/end-of-day — see `SPEC_RECOVERY_MESSAGING.md` §1.1.
    @Test func bundledLibraryMeetsPoolFloorInEveryCell() {
        let library = ActivityLibrary.load()
        #expect(!library.isEmpty, "Bundled activities.json should load")

        for band in Activity.DurationBand.allCases {
            for tod in Activity.TimeOfDay.allCases {
                let pool = library.filter { $0.band == band && $0.suitableTimes.contains(tod) }
                let categories = Set(pool.map(\.category))
                #expect(pool.count >= 6,
                        "\(band.rawValue)/\(tod.rawValue) holds \(pool.count) activities; below 6 the recency rule disables itself")
                #expect(categories.count >= 3,
                        "\(band.rawValue)/\(tod.rawValue) spans \(categories.count) categories; below 3 the category rule can never fire")
            }
        }
    }

    /// The user-visible property the floor above exists to buy: walking a day's worth of
    /// breaks through the real library never serves the same activity twice running.
    @Test func bundledLibraryNeverRepeatsBackToBack() {
        let library = ActivityLibrary.load()
        // One hour inside each time-of-day bucket for a 09:00–18:00 workday.
        for hour in [10, 12, 15, 17] {
            for breakMinutes in [5, 8] {
                var recent: [String] = []
                var lastCategory: Activity.Category?
                for _ in 0..<200 {
                    let pick = select(breakMinutes: breakMinutes, hour: hour,
                                      recent: recent, lastCategory: lastCategory,
                                      from: library)
                    #expect(pick != nil)
                    guard let pick else { break }
                    #expect(pick.id != recent.first,
                            "\(pick.id) served twice running at \(hour):00, \(breakMinutes)-min break")
                    recent.insert(pick.id, at: 0)
                    lastCategory = pick.category
                }
            }
        }
    }
}
