import Foundation

/// A standing reminder to do one small thing, delivered on a break —
/// PURPOSE principle 8.
///
/// A nudge is not a task. It has no completion state, is never acknowledged,
/// and is never logged: the app says it once and forgets it. `because` is the
/// half that does the work — the same posture as `ReminderMessages`, where the
/// line is the argument for the thing rather than a label on it.
struct Nudge: Equatable {
    let id: String
    /// The ask, in one short line.
    let ask: String
    /// Why it matters. Shown quieter, directly underneath.
    let because: String
    /// Minutes since midnight. The nudge rides the earliest break that starts
    /// at or after this time — never a break before it.
    let afterMinutes: Int
}

/// The single quiet line above the activity on the break card: either the day's
/// rest-argument or a due nudge. Never both — on a nudge break the card keeps
/// exactly the shape it always has, and only the words change.
enum BreakCaption: Equatable {
    case reminder(String)
    case nudge(Nudge)
}

/// The nudge library, and the rule that places nudges on breaks.
///
/// Curated in source like the activity library and the reminder pool: no
/// editor, no settings pane, no per-nudge persistence. Delivery state is
/// *derived* rather than stored — today's break start times are enough to
/// recompute, deterministically, which nudge each break carried.
enum Nudges {
    static let all: [Nudge] = [
        Nudge(
            id: "water",
            ask: "Top up your water bottle, if you haven't already.",
            because: "A quick refill now beats trying to catch up on hydration once the afternoon dip hits.",
            afterMinutes: 16 * 60 + 20
        ),
    ]

    /// The nudge a break starting at `now` should carry, if any.
    ///
    /// `shownBreakStartsToday` is every break earlier today that actually put a
    /// card on screen, in chronological order. Re-deriving the whole day's
    /// assignment on each break is what makes "once a day" work without
    /// storing anything.
    static func forBreak(
        startingAt now: Date,
        shownBreakStartsToday: [Date],
        from pool: [Nudge] = Nudges.all,
        calendar: Calendar = .current
    ) -> Nudge? {
        // `assign` always returns one slot per break, and `now` is always the
        // last of them, so the final slot is this break's answer.
        guard let mine = assign(
            to: shownBreakStartsToday + [now], from: pool, calendar: calendar
        ).last else { return nil }
        return mine
    }

    /// Walk a day's breaks in order, handing each the most recently due nudge
    /// still unspent. A nudge that isn't due yet waits; a nudge whose break
    /// never came is simply not delivered that day.
    ///
    /// Most-recently-due wins because a nudge decays: at 16:30 "eat something
    /// before you leave" still lands, while an 11:00 nudge has mostly expired.
    /// The older one falls through to the next break, where it still has a shot.
    static func assign(
        to breakStarts: [Date],
        from pool: [Nudge] = Nudges.all,
        calendar: Calendar = .current
    ) -> [Nudge?] {
        // Descending by time, ties broken by declaration order — `sorted` is
        // not stable, and the assignment must not depend on the sort's whim.
        var unspent = pool.enumerated().sorted { a, b in
            a.element.afterMinutes == b.element.afterMinutes
                ? a.offset < b.offset
                : a.element.afterMinutes > b.element.afterMinutes
        }.map { $0.element }

        return breakStarts.map { (start) -> Nudge? in
            let minutes = TimeFormat.minutesSinceMidnight(from: start, calendar: calendar)
            guard let due = unspent.firstIndex(where: { $0.afterMinutes <= minutes }) else { return nil }
            return unspent.remove(at: due)
        }
    }
}
