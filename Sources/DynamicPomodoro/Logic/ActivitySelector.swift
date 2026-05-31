import Foundation

/// Activity selection rules — §4.3.
///
/// Filters: duration band, time-of-day suitability.
/// Soft rules: not shown in last 3, no category repeat back-to-back.
/// Falls back gracefully when filters exclude everything.
enum ActivitySelector {
    static func select(
        from library: [Activity],
        breakMinutes: Int,
        now: Date,
        recentActivityIDs: [String],   // most-recent first
        lastCategory: Activity.Category?,
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

        // Filter 1: hard constraints (band, time-of-day)
        var pool = library.filter { $0.band == band && $0.suitableTimes.contains(tod) }

        // If duration band empties the pool (e.g. all "short" activities filtered out by time
        // of day), relax the band — keeping time-of-day is more important than band fit.
        if pool.isEmpty {
            pool = library.filter { $0.suitableTimes.contains(tod) }
        }

        // Last-resort: anything.
        if pool.isEmpty { pool = library }
        if pool.isEmpty { return nil }

        func soft(_ predicate: (Activity) -> Bool) {
            let f = pool.filter(predicate); if !f.isEmpty { pool = f }
        }

        soft { !recencyWindow.contains($0.id) }
        if let lastCat = lastCategory { soft { $0.category != lastCat } }

        return pool.randomElement(using: &rng)
    }
}
