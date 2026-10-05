import Foundation

/// What the stats window plots: focus alone, or focus with the break time
/// that sat between the sessions.
///
/// A named pair rather than a `Bool` in the view, because five things read
/// it — the bars, the axis ceiling, the window total, the week footers and
/// the header line — and they must all mean the same thing by it. Pure, so
/// both read-outs are checkable without a window.
enum StatsMeasure: Equatable {
    /// Focus only.
    case focus
    /// Focus plus the breaks that were actually taken — the time the day
    /// spent at the desk, which is what a working day compares against.
    case focusAndBreak

    /// Header line. Lives here rather than in the view so the chart cannot
    /// be titled one thing while it plots another.
    var title: String {
        switch self {
        case .focus: return "Focus per day"
        case .focusAndBreak: return "Focus + break per day"
        }
    }
}

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
    var focusSeconds: Int { seconds(.focus) }

    /// What this day contributes under the given read-out. A skipped break
    /// adds nothing under either — `DailyStats.contribution` drops it, since
    /// the break never happened — so break time here is time a break took.
    func seconds(_ measure: StatsMeasure) -> Int {
        switch measure {
        case .focus: return stats.focusSeconds
        case .focusAndBreak: return stats.totalSeconds
        }
    }
}

/// Seven days, Monday to Sunday (`WeekGrid`).
struct FocusWeek: Equatable, Identifiable {
    let days: [FocusDay]

    var id: Date { start }
    var start: Date { days.first?.date ?? .distantPast }
    var end: Date { days.last?.date ?? .distantPast }
    var focusSeconds: Int { seconds(.focus) }

    func seconds(_ measure: StatsMeasure) -> Int {
        days.reduce(0) { $0 + $1.seconds(measure) }
    }
}

/// The grid of days both stats pages draw on: whole weeks, Monday to
/// Sunday, ending with the week `now` falls in.
///
/// Monday to Sunday by definition, not by locale: a week here is the
/// working week the user's hours are counted against, and the two pages
/// must agree with each other about which week a Sunday belongs to. The
/// calendar still supplies the time zone and the day boundaries (so a DST
/// day is still one day), only its first weekday is overruled.
enum WeekGrid {
    /// The trailing `weekCount` weeks, oldest first; each week is its seven
    /// start-of-day dates in order. Every day is present, because a gap is
    /// data (a day off, a day the tool went unused) and dropping it would
    /// silently compress whatever is drawn on top.
    static func days(weekCount: Int, calendar: Calendar, now: Date) -> [[Date]] {
        guard weekCount > 0 else { return [] }
        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let today = weekCalendar.startOfDay(for: now)
        guard let thisWeek = weekCalendar.dateInterval(of: .weekOfYear, for: today),
              let firstDay = weekCalendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeek.start)
        else { return [] }

        return (0..<weekCount).compactMap { week -> [Date]? in
            let days = (0..<7).compactMap { offset -> Date? in
                guard let raw = weekCalendar.date(byAdding: .day, value: week * 7 + offset, to: firstDay)
                else { return nil }
                // Re-normalise: adding days lands on the same wall-clock
                // time, which a DST transition can move off midnight, and
                // callers bucket their entries by true starts-of-day.
                return weekCalendar.startOfDay(for: raw)
            }
            return days.count == 7 ? days : nil
        }
    }
}

/// Folds the session log into a trailing run of whole calendar weeks — the
/// data behind the stats window's totals page. Pure: the caller supplies
/// `now` and the calendar, so tests need no clock.
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
        let today = calendar.startOfDay(for: now)

        // Bucket the log once by day rather than re-filtering it per day:
        // the fold is O(entries), not O(entries × days).
        var byDay: [Date: DailyStats] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.startedAt)
            byDay[day] = (byDay[day] ?? .empty) + DailyStats.contribution(of: entry)
        }

        return WeekGrid.days(weekCount: weekCount, calendar: calendar, now: now).map { days in
            FocusWeek(days: days.map { day in
                FocusDay(date: day, stats: byDay[day] ?? .empty, isFuture: day > today)
            })
        }
    }
}
