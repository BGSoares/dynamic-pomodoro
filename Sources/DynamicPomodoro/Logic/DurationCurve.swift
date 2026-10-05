import Foundation

/// Computes focus-session duration per §3 of the spec.
///
/// - First session of the day (by calendar date) is always the start-of-day
///   minimum: the warm-up length, whatever the clock says.
/// - Before the workday: the start minimum. After it: the end minimum.
/// - Otherwise: two half-cosines meeting at the workday midpoint – rising
///   from the start minimum to `max`, then falling from `max` to the end
///   minimum. With equal minimums this is the original symmetric bell; a
///   higher end minimum makes the afternoon taper less, which is the whole
///   reason the floor is two numbers rather than one.
enum DurationCurve {
    /// Minutes.
    static func focusDuration(
        now: Date,
        isFirstSessionOfDay: Bool,
        settings: Settings,
        calendar: Calendar = .current
    ) -> Int {
        let minStart = settings.minFocusStartMinutes
        let minEnd = settings.minFocusEndMinutes
        let maxD = settings.maxFocusMinutes

        if isFirstSessionOfDay {
            return minStart
        }

        let nowMin = TimeFormat.minutesSinceMidnight(from: now, calendar: calendar)
        let start = settings.workdayStartMinutes
        let end = settings.workdayEndMinutes

        if nowMin < start { return minStart }
        if nowMin > end { return minEnd }

        let midpoint = Double(settings.midpointMinutes)
        let half = Double(settings.halfDayMinutes)
        // Each half of the day has its own floor. The peak is shared, so the
        // two halves meet at the midpoint without a step.
        let floor = Double(nowMin) < midpoint ? minStart : minEnd
        guard half > 0 else { return floor }

        let distance = abs(Double(nowMin) - midpoint)
        let ratio = min(distance / half, 1.0)
        // cosine: 1 at midpoint, 0 at workday edges
        let weight = 0.5 * (1.0 + cos(.pi * ratio))
        let duration = Double(floor) + Double(maxD - floor) * weight
        return Int(duration.rounded())
    }
}
