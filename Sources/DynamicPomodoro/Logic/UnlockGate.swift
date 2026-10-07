import Foundation

/// Pure decision logic for the unlock auto-start countdown (SPEC_UNLOCK_AUTOSTART.md §3).
/// No AppKit, no singletons — every clause is exercisable with a synthetic `Date`.
enum UnlockGate {
    /// Whether an unlock should offer the auto-start countdown.
    ///
    /// - `phase` must be idle — never interrupt a running focus, a pending
    ///   break, or a running break.
    /// - `lastActivityEnd` (the end of the log's latest entry, of any kind –
    ///   entries are logged when a phase *ends*, so a running one hasn't
    ///   logged yet and the phase check above is what says nothing is running)
    ///   must exist and fall within `windowMinutes` of `now` — an unlock
    ///   within a couple of hours of the loop last turning is a return to
    ///   it; one after that is a new day-part, and a negative gap (clock
    ///   skew) is never "just back".
    ///
    /// Every qualifying unlock offers: a cancelled countdown says "not now",
    /// not "not again", and costs one click to repeat.
    static func shouldOffer(
        phase: PomodoroState.Phase,
        lastActivityEnd: Date?,
        now: Date,
        windowMinutes: Int
    ) -> Bool {
        guard case .idle = phase else { return false }
        guard let lastActivityEnd else { return false }
        let elapsed = now.timeIntervalSince(lastActivityEnd)
        guard elapsed >= 0 else { return false }
        return elapsed <= TimeInterval(windowMinutes * 60)
    }

    /// Whether a countdown that has reached its deadline should still fire
    /// the auto-start, vs. having overshot enough (machine slept, run loop
    /// stalled) that nobody was there to see it end — the same philosophy as
    /// `PomodoroReducer.missedDeadlineGraceSeconds`: never start a session on
    /// behalf of someone who provably wasn't there for the decision.
    static func shouldStillFire(deadline: Date, now: Date, graceSeconds: TimeInterval = 3) -> Bool {
        now.timeIntervalSince(deadline) <= graceSeconds
    }
}
