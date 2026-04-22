import Foundation

/// Computes focus-session duration per §3 of the spec.
///
/// - First session of the day (by calendar date) is always `min`.
/// - Outside workday hours: clamped to `min`.
/// - Otherwise: cosine curve between `min` and `max`, peaking at workday midpoint.
enum DurationCurve {
    /// Minutes.
    static func focusDuration(
        now: Date,
        isFirstSessionOfDay: Bool,
        settings: Settings,
        calendar: Calendar = .current
    ) -> Int {
        let minD = settings.minFocusMinutes
        let maxD = settings.maxFocusMinutes

        if isFirstSessionOfDay {
            return minD
        }

        let nowMin = TimeFormat.minutesSinceMidnight(from: now, calendar: calendar)
        let start = settings.workdayStartMinutes
        let end = settings.workdayEndMinutes

        if nowMin < start || nowMin > end {
            return minD
        }

        let midpoint = Double(settings.midpointMinutes)
        let half = Double(settings.halfDayMinutes)
        guard half > 0 else { return minD }

        let t = Double(nowMin)
        let distance = abs(t - midpoint)
        let ratio = min(distance / half, 1.0)
        // cosine: 1 at midpoint, 0 at workday edges
        let weight = 0.5 * (1.0 + cos(.pi * ratio))
        let duration = Double(minD) + Double(maxD - minD) * weight
        return Int(duration.rounded())
    }

    /// Samples the curve every `stepMinutes` across the workday for the preview UI.
    /// Returned pairs are (minutes-since-midnight, duration-minutes).
    static func curveSamples(settings: Settings, stepMinutes: Int = 15) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var m = settings.workdayStartMinutes
        let calendar = Calendar.current
        // Use an arbitrary reference date to avoid DST weirdness during sampling.
        var base = DateComponents()
        base.year = 2025; base.month = 1; base.day = 1
        let baseDate = calendar.date(from: base) ?? Date()

        while m <= settings.workdayEndMinutes {
            let d = calendar.date(byAdding: .minute, value: m, to: baseDate) ?? baseDate
            let dur = focusDuration(now: d, isFirstSessionOfDay: false, settings: settings, calendar: calendar)
            out.append((m, dur))
            m += stepMinutes
        }
        return out
    }
}
