import Foundation

/// Activity selection rules — §4.3.
///
/// Filters: duration band, time-of-day suitability, user-disabled categories.
/// Soft rules: not shown in last 3, no category repeat back-to-back.
/// Falls back gracefully when filters exclude everything.
enum ActivitySelector {
    static func select(
        from library: [Activity],
        breakMinutes: Int,
        now: Date,
        recentActivityIDs: [String],   // most-recent first
        lastCategory: Activity.Category?,
        disabledCategories: Set<String>,
        settings: Settings,
        calendar: Calendar = .current,
        rng: inout SystemRandomNumberGenerator
    ) -> Activity? {
        guard !library.isEmpty else { return nil }

        let band = BreakLogic.durationBand(forBreakMinutes: breakMinutes)
        let nowMin = TimeFormat.minutesSinceMidnight(from: now, calendar: calendar)
        let tod = Activity.TimeOfDay.fromClock(
            minutesSinceMidnight: nowMin,
            workdayStart: settings.workdayStartMinutes,
            workdayEnd: settings.workdayEndMinutes
        )
        let recencyWindow = Set(recentActivityIDs.prefix(3))

        // Filter 1: hard constraints (band, time-of-day, enabled category)
        func passesHard(_ a: Activity) -> Bool {
            guard a.band == band else { return false }
            guard a.suitableTimes.contains(tod) else { return false }
            guard !disabledCategories.contains(a.category.rawValue) else { return false }
            return true
        }

        var pool = library.filter(passesHard)

        // If duration band empties the pool (e.g. all "short" activities filtered out by time
        // of day), relax the band — keeping time-of-day is more important than band fit.
        if pool.isEmpty {
            pool = library.filter { a in
                a.suitableTimes.contains(tod) &&
                !disabledCategories.contains(a.category.rawValue)
            }
        }

        // Last-resort: anything enabled.
        if pool.isEmpty {
            pool = library.filter { !disabledCategories.contains($0.category.rawValue) }
        }
        if pool.isEmpty { return nil }

        // Soft filter: exclude recent 3 if possible
        let withoutRecent = pool.filter { !recencyWindow.contains($0.id) }
        if !withoutRecent.isEmpty { pool = withoutRecent }

        // Soft filter: avoid category repeat back-to-back if possible
        if let lastCat = lastCategory {
            let withoutLastCat = pool.filter { $0.category != lastCat }
            if !withoutLastCat.isEmpty { pool = withoutLastCat }
        }

        // Soft cap: cycling-news headlines are reading, not movement. They get
        // ~25% of selections at most — when an unbiased pick lands outside the
        // quota, drop news items from the pool. This keeps "Show cycling news
        // during breaks" from monopolising the rotation when many headlines
        // are cached, without ever forcing a news pick.
        if !shouldAllowCyclingNewsThisPick(rng: &rng) {
            let withoutNews = pool.filter { $0.category != .cyclingNews }
            if !withoutNews.isEmpty { pool = withoutNews }
        }

        // Weighted random — equal weights here; kept as an extension point.
        return pool.randomElement(using: &rng)
    }

    private static let cyclingNewsQuota: Double = 0.25

    private static func shouldAllowCyclingNewsThisPick(rng: inout SystemRandomNumberGenerator) -> Bool {
        Double.random(in: 0..<1, using: &rng) < cyclingNewsQuota
    }
}
