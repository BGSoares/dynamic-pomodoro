import Foundation

/// One calendar day in the stats window.
struct FocusDay: Equatable, Identifiable {
    /// Start of the day, user-local.
    let date: Date
    let stats: DailyStats
    /// A slot later than the day `now` fell on — the tail of the current
    /// week, which hasn't happened yet. Drawn as an empty slot rather than
    /// as a zero, because "no focus yet" and "no focus" are different claims.
    let isFuture: Bool

    var id: Date { date }
    var focusSeconds: Int { stats.focusSeconds }
}

/// Seven days, aligned to the locale's first weekday.
struct FocusWeek: Equatable, Identifiable {
    let days: [FocusDay]

    var id: Date { start }
    var start: Date { days.first?.date ?? .distantPast }
    var end: Date { days.last?.date ?? .distantPast }
    var focusSeconds: Int { days.reduce(0) { $0 + $1.focusSeconds } }
}

/// Folds the session log into a trailing run of whole calendar weeks — the
/// data behind the stats window. Pure: the caller supplies `now` and the
/// calendar, so tests need no clock and week boundaries are the locale's
/// opinion rather than ours.
///
/// Whole weeks rather than a rolling 28 days: a rolling window slices weeks
/// mid-stride, so a week total means "the seven days ending today", which is
/// not a week anyone recognises. The cost is that the current week is
/// partial, and the empty future slots say so on the face of the chart.
enum FocusHistory {
    /// Four weeks. Long enough to see a shape across a month, short enough
    /// that a day is still a readable bar rather than a hairline.
    static let defaultWeekCount = 4

    /// The trailing `weekCount` calendar weeks ending with the one `now`
    /// falls in, oldest first. Every week has exactly seven days and every
    /// day is present: a day with no sessions carries `.empty` stats, since
    /// a gap is data (a day off, a day the tool went unused) and dropping it
    /// would silently compress the axis.
    static func weeks(
        from entries: [SessionLogEntry],
        weekCount: Int = defaultWeekCount,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [FocusWeek] {
        guard weekCount > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let firstDay = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeek.start)
        else { return [] }

        // Bucket the log once by day rather than re-filtering it per day:
        // the fold is O(entries), not O(entries × days).
        var byDay: [Date: DailyStats] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.startedAt)
            byDay[day] = (byDay[day] ?? .empty) + DailyStats.contribution(of: entry)
        }

        return (0..<weekCount).compactMap { week -> FocusWeek? in
            let days: [FocusDay] = (0..<7).compactMap { offset -> FocusDay? in
                guard let raw = calendar.date(byAdding: .day, value: week * 7 + offset, to: firstDay)
                else { return nil }
                // Re-normalise: adding days lands on the same wall-clock
                // time, which a DST transition can move off midnight, and
                // the bucket keys above are true starts-of-day.
                let day = calendar.startOfDay(for: raw)
                return FocusDay(date: day, stats: byDay[day] ?? .empty, isFuture: day > today)
            }
            guard days.count == 7 else { return nil }
            return FocusWeek(days: days)
        }
    }
}
