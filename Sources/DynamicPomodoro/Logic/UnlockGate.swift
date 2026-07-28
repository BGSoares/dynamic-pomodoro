import Foundation

/// Pure decision logic for the unlock auto-start countdown (SPEC_UNLOCK_AUTOSTART.md §3).
/// No AppKit, no singletons — every clause is exercisable with a synthetic `Date`.
enum UnlockGate {
    /// Whether an unlock should offer the auto-start countdown.
    ///
    /// - `phase` must be idle — never interrupt a running focus, a pending
    ///   break, or a running break.
    /// - `lastBreakEnd` must exist — the log's last transition must be a
    ///   break ending, i.e. nothing has run since.
    /// - `lastBreakEnd` must differ from `suppressedBreakEnd` — one offer
    ///   per break end; a cancelled offer doesn't recur for the same one.
    /// - the gap to `now` must fall within `windowMinutes` — a stale
    ///   break end is a new day-part, not a continuation, and a negative gap
    ///   (clock skew) is never "just back".
    static func shouldOffer(
        phase: PomodoroState.Phase,
        lastBreakEnd: Date?,
        suppressedBreakEnd: Date?,
        now: Date,
        windowMinutes: Int
    ) -> Bool {
        guard case .idle = phase else { return false }
        guard let lastBreakEnd else { return false }
        guard lastBreakEnd != suppressedBreakEnd else { return false }
        let elapsed = now.timeIntervalSince(lastBreakEnd)
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
