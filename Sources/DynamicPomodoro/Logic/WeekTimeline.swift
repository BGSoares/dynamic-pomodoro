import Foundation

/// One logged session or break placed on its day: the wall-clock span the
/// stats window's timeline page draws.
struct TimelineBlock: Equatable, Identifiable {
    let entry: SessionLogEntry
    /// Wall-clock seconds since the day's midnight. A span that runs past
    /// midnight is clipped to the end of the day it started on.
    let startSecond: Int
    let endSecond: Int

    var id: Date { entry.startedAt }
    var kind: SessionLogEntry.Kind { entry.kind }
}

/// One calendar day on the timeline page.
struct TimelineDay: Equatable, Identifiable {
    /// Start of the day, user-local.
    let date: Date
    /// Chronological. Skipped breaks are absent: no time was taken, so
    /// there is nothing to draw – the same rule `DailyStats` applies.
    let blocks: [TimelineBlock]
    /// A day later than the one `now` fell on; drawn as an empty slot.
    let isFuture: Bool

    var id: Date { date }

    /// First start to last end of what was logged, seconds since midnight –
    /// the day's working span, which is the question this page answers.
    var span: ClosedRange<Int>? {
        guard let first = blocks.first?.startSecond,
              let last = blocks.map(\.endSecond).max()
        else { return nil }
        return first...max(first, last)
    }
}

/// Seven days, Monday to Sunday (`WeekGrid`).
struct TimelineWeek: Equatable, Identifiable {
    let days: [TimelineDay]

    var id: Date { start }
    var start: Date { days.first?.date ?? .distantPast }
    var end: Date { days.last?.date ?? .distantPast }
    var isEmpty: Bool { days.allSatisfy { $0.blocks.isEmpty } }
}

/// Folds the session log into the timeline page's weeks. Pure, like
/// `FocusHistory`, and built on the same `WeekGrid`, so a day sits in the
/// same week on both pages.
enum WeekTimeline {
    /// Last week and this week: enough to fill in a timesheet for the week
    /// that just ended and to check the one in progress.
    static let defaultWeekCount = 2

    static func weeks(
        from entries: [SessionLogEntry],
        weekCount: Int = defaultWeekCount,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [TimelineWeek] {
        let today = calendar.startOfDay(for: now)

        var byDay: [Date: [TimelineBlock]] = [:]
        for entry in entries where entry.kind != .breakSkipped {
            let day = calendar.startOfDay(for: entry.startedAt)
            byDay[day, default: []].append(block(for: entry, calendar: calendar))
        }

        return WeekGrid.days(weekCount: weekCount, calendar: calendar, now: now).map { days in
            TimelineWeek(days: days.map { day in
                TimelineDay(
                    date: day,
                    blocks: (byDay[day] ?? []).sorted { $0.startSecond < $1.startSecond },
                    isFuture: day > today
                )
            })
        }
    }

    /// The hours the axis must cover, in minutes since midnight: the
    /// configured workday, widened to the earliest start and latest end
    /// logged in `weeks`, on whole hours. One axis for every week shown, so
    /// switching weeks never rescales the day under the eye.
    static func axis(
        covering weeks: [TimelineWeek],
        workdayStartMinutes: Int,
        workdayEndMinutes: Int
    ) -> ClosedRange<Int> {
        let blocks = weeks.flatMap(\.days).flatMap(\.blocks)
        let earliest = min(workdayStartMinutes * 60, blocks.map(\.startSecond).min() ?? .max)
        let latest = max(workdayEndMinutes * 60, blocks.map(\.endSecond).max() ?? .min)
        let lower = earliest / 3600 * 60
        let upper = min(24 * 60, (latest + 3599) / 3600 * 60)
        return lower...max(upper, lower + 60)
    }

    private static func block(for entry: SessionLogEntry, calendar: Calendar) -> TimelineBlock {
        let start = TimeFormat.secondsSinceMidnight(from: entry.startedAt, calendar: calendar)
        let end: Int
        if entry.endedAt < entry.startedAt {
            // A hand-edited or clock-jumped entry: draw it as a point rather
            // than running backwards.
            end = start
        } else if calendar.isDate(entry.endedAt, inSameDayAs: entry.startedAt) {
            end = TimeFormat.secondsSinceMidnight(from: entry.endedAt, calendar: calendar)
        } else {
            end = 24 * 3600
        }
        return TimelineBlock(entry: entry, startSecond: start, endSecond: max(start, end))
    }
}
