import Foundation

/// Pure-Swift state machine. No AppKit, no Combine — every transition is exercised
/// with a synthetic Date, so tests need no real timers. Effects are returned as values
/// for `TimerEngine` to interpret.

// MARK: - State

struct PomodoroState: Equatable {
    enum Phase: Equatable {
        case idle
        case focus(deadline: Date, startedAt: Date, planned: Int)
        /// Focus is done but a call is live (mic in use) — the break is owed
        /// and starts on its own the moment the call ends.
        case breakPending(planned: Int, since: Date)
        case breakRunning(
            deadline: Date,
            startedAt: Date,
            planned: Int,
            activity: Activity,
            /// The day's reminder line (§4.5), shown above the activity.
            caption: String?
        )
    }

    var phase: Phase = .idle
    /// Seconds left in the current phase. Recomputed on each `.tick`.
    var remainingSeconds: Int = 0
    /// Total seconds for the current phase (for progress rendering).
    var totalSeconds: Int = 0
    /// Set once the 30s-into-break screen lock has fired for the current break.
    /// Resets when the phase leaves `.breakRunning`.
    var breakLockFired: Bool = false
    /// The current break was started by hand over a live call ("Start break
    /// now"). That break runs in full – overlay, lock and all – because the
    /// user just asked for it; any other break defers to a call that begins
    /// during it (principle 7). Resets with the phase, like `breakLockFired`.
    var breakOverridesCall: Bool = false
}

extension PomodoroState.Phase {
    /// Integer discriminator that ignores associated values — used to
    /// deduplicate phase-change events that differ only in deadline/activity data.
    var tag: Int {
        switch self {
        case .idle: 0
        case .focus: 1
        case .breakPending: 2
        case .breakRunning: 3
        }
    }
}

extension PomodoroState {
    var currentActivity: Activity? {
        if case .breakRunning(_, _, _, let a, _) = phase { return a }
        return nil
    }
    var currentBreakCaption: String? {
        if case .breakRunning(_, _, _, _, let c) = phase { return c }
        return nil
    }

    /// When the current phase is `.breakPending`, the moment it began.
    var pendingSince: Date? {
        if case .breakPending(_, let since) = phase { return since }
        return nil
    }

    /// 0...1 elapsed. Returns 0 when no phase is active.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(totalSeconds)
    }

    var remainingFormatted: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}

// MARK: - Action

enum PomodoroAction {
    case startFocus(now: Date)
    case abandonFocus(now: Date)
    case skipBreak(now: Date)
    /// Start an owed break immediately, overriding call detection — the
    /// manual escape valve on the pending screen.
    case startPendingBreak(now: Date)
    case tick(now: Date)
    case fastForward(now: Date)
}

// MARK: - Effect

enum PomodoroEffect: Equatable {
    /// `silent` exists for principle 7: a notification posted because of a
    /// live call must not put a sound in the room the call is happening in.
    /// Every other notification keeps the default sound.
    case notify(title: String, body: String, silent: Bool)
    case logSession(SessionLogEntry)
    /// Pause whatever media is playing, as a break starts with the
    /// setting on. One-way: nothing playing means nothing happens.
    case pauseMedia
    case playFocusCompleteChime
    case playBreakCompleteChime
    case startTicker
    case stopTicker
    case lockScreen
    /// A completed hold-to-skip offers the auto-start countdown
    /// (SPEC_LOOP_CONTINUITY.md §2) — never the call-cap skip (§2.2).
    /// Carries `now` so the countdown's gate check uses the same instant
    /// the skip was logged at.
    case offerAutoStart(now: Date)
    /// A break completed (not skipped, not capped) while the screen was
    /// known unlocked brings the main window forward (§3). Emitted
    /// unconditionally from `completeBreak`; the F2/F3 gate lives with the
    /// window presenter, not the reducer.
    case presentMainWindow
    /// Any path into `.focus` hides the main window (§4.2) — it's the one
    /// state that never shows it.
    case hideMainWindow
}

// MARK: - Reducer

enum PomodoroReducer {
    /// Seconds after a break starts before the screen auto-locks.
    /// Long enough to read the activity card; short enough that walking away
    /// without the lock would be a security risk.
    static let breakLockDelaySeconds: TimeInterval = 30

    /// Seconds past a focus deadline beyond which the session is treated as
    /// interrupted-by-absence (lid closed, machine asleep) rather than
    /// completed. While the app is awake, ticks arrive every second, so an
    /// overshoot this large can only mean nobody was there: no fabricated
    /// completion, no break, no chime, no screen lock on wake.
    static let missedDeadlineGraceSeconds: TimeInterval = 180

    /// How long an owed break waits for a call to end before the moment has
    /// passed. Bounds the damage of a stuck call signal (an always-on mic
    /// tool would otherwise defer breaks forever).
    static let breakPendingCapSeconds: TimeInterval = 30 * 60

    static func reduce(
        _ state: inout PomodoroState,
        _ action: PomodoroAction,
        settings: Settings,
        log: SessionLogStore,
        library: [Activity],
        isOnCall: Bool,
        rng: inout some RandomNumberGenerator,
        calendar: Calendar = .current
    ) -> [PomodoroEffect] {
        switch action {
        case .startFocus(let now):
            // Re-entrant starts are ignored — once running, you finish or abandon.
            guard case .idle = state.phase else { return [] }
            let minutes = DurationCurve.focusDuration(
                now: now,
                isFirstSessionOfDay: !log.hasCompletedFocusToday(calendar: calendar, now: now),
                settings: settings,
                calendar: calendar
            )
            let sessionSeconds = TimeScale.seconds(ofMinutes: minutes)
            let deadline = now.addingTimeInterval(TimeInterval(sessionSeconds))
            beginPhase(&state, .focus(deadline: deadline, startedAt: now, planned: minutes), seconds: sessionSeconds)
            return [
                .startTicker,
                .notify(title: "Focus started", body: "\(minutes) min.", silent: false),
                .hideMainWindow,
            ]

        case .abandonFocus(let now):
            guard case .focus(_, let startedAt, let planned) = state.phase else { return [] }
            resetToIdle(&state)
            return [
                .stopTicker,
                .logSession(SessionLogEntry(kind: .focusAbandoned, from: startedAt, to: now, minutes: planned)),
            ]

        case .skipBreak(let now):
            guard case .breakRunning(_, let startedAt, let planned, let activity, _) = state.phase else { return [] }
            resetToIdle(&state)
            // .logSession must precede .offerAutoStart: the offer reads
            // the log's latest entry, which must already be this one
            // (SPEC_LOOP_CONTINUITY.md §2.4). Effects run in array order.
            return [
                .stopTicker,
                .logSession(SessionLogEntry(kind: .breakSkipped, from: startedAt, to: now, minutes: planned, activity: activity.id)),
                .offerAutoStart(now: now),
            ]

        case .tick(let now):
            switch state.phase {
            case .idle:
                return [.stopTicker]

            case .focus(let deadline, let startedAt, let planned):
                if now.timeIntervalSince(deadline) > TimeScale.seconds(Self.missedDeadlineGraceSeconds) {
                    // Slept across the deadline. The ticker died before the
                    // deadline, so actual focus was < planned; log it as
                    // abandoned at the deadline (upper bound) and go idle.
                    resetToIdle(&state)
                    return [
                        .stopTicker,
                        .logSession(SessionLogEntry(kind: .focusAbandoned, from: startedAt, to: deadline, minutes: planned)),
                    ]
                }
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
                state.remainingSeconds = remaining
                if remaining == 0 {
                    if isOnCall {
                        // Never throw the overlay + screen lock into a live
                        // meeting. The focus still completed at its deadline;
                        // the break is owed and waits for the call to end.
                        // No chime — it could bleed into the call.
                        beginPhase(&state, .breakPending(planned: planned, since: deadline), seconds: 0)
                        return [
                            .logSession(SessionLogEntry(kind: .focusCompleted, from: startedAt, to: deadline, minutes: planned)),
                            // Silent for the same reason the chime is withheld
                            // (principle 7): a notification ping bleeds into a
                            // call exactly like a chime does.
                            .notify(title: "Focus complete", body: "Break starts when your call ends.", silent: true),
                        ]
                    }
                    return completeFocus(state: &state, now: now, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)
                }
                return []

            case .breakPending(let planned, let since):
                if now.timeIntervalSince(since) > TimeScale.seconds(Self.breakPendingCapSeconds) {
                    // The call outlasted the break's moment. Go idle; the
                    // absent recovery is logged honestly as a skipped break.
                    let breakMinutes = BreakLogic.breakDuration(forFocusMinutes: planned)
                    resetToIdle(&state)
                    return [
                        .stopTicker,
                        .logSession(SessionLogEntry(kind: .breakSkipped, from: since, to: now, minutes: breakMinutes)),
                    ]
                }
                if !isOnCall {
                    return startBreak(state: &state, planned: planned, now: now, overridingCall: false, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)
                }
                return []

            case .breakRunning(let deadline, let startedAt, _, _, _):
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
                state.remainingSeconds = remaining
                if remaining == 0 {
                    return completeBreak(state: &state, now: now, isOnCall: isOnCall)
                }
                if !state.breakLockFired,
                   now.timeIntervalSince(startedAt) >= TimeScale.seconds(breakLockDelaySeconds) {
                    state.breakLockFired = true
                    // A call that began inside the break's first half-minute
                    // gets no login window thrown over it (principle 7). The
                    // break still runs; only the lock is withheld, and for
                    // good – a lock fired after the call would land on
                    // whatever the call left behind. The break the user
                    // started by hand over a call is the exception: they
                    // asked for all of it.
                    guard !isOnCall || state.breakOverridesCall else { return [] }
                    return [.lockScreen]
                }
                return []
            }

        case .startPendingBreak(let now):
            guard case .breakPending(let planned, _) = state.phase else { return [] }
            return startBreak(state: &state, planned: planned, now: now, overridingCall: isOnCall, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)

        case .fastForward(let now):
            switch state.phase {
            case .focus(_, let startedAt, let planned):
                // Mirror the real deadline: a live call defers here too, so
                // the pending flow is exercisable via the test shortcut. A
                // second fast-forward force-starts the break from pending.
                if isOnCall {
                    beginPhase(&state, .breakPending(planned: planned, since: now), seconds: 0)
                    return [
                        .logSession(SessionLogEntry(kind: .focusCompleted, from: startedAt, to: now, minutes: planned)),
                        .notify(title: "Focus complete", body: "Break starts when your call ends.", silent: true),
                    ]
                }
                return completeFocus(state: &state, now: now, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)
            case .breakPending(let planned, _):
                return startBreak(state: &state, planned: planned, now: now, overridingCall: isOnCall, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)
            case .breakRunning:
                return completeBreak(state: &state, now: now, isOnCall: isOnCall)
            case .idle:
                return []
            }
        }
    }

    // MARK: - Transitions

    private static func completeFocus(
        state: inout PomodoroState,
        now: Date,
        settings: Settings,
        log: SessionLogStore,
        library: [Activity],
        rng: inout some RandomNumberGenerator,
        calendar: Calendar
    ) -> [PomodoroEffect] {
        guard case .focus(_, let startedAt, let planned) = state.phase else { return [] }
        let focusLog = PomodoroEffect.logSession(
            SessionLogEntry(kind: .focusCompleted, from: startedAt, to: now, minutes: planned)
        )
        return [focusLog] + startBreak(state: &state, planned: planned, now: now, overridingCall: false, settings: settings, log: log, library: library, rng: &rng, calendar: calendar)
    }

    /// Enter `.breakRunning` for a completed focus of `planned` minutes.
    /// Shared by the immediate path (focus deadline, no call) and the
    /// deferred path (`.breakPending` once the call ends or is overridden).
    /// `overridingCall` is true only on the override: a break started by
    /// hand while the mic is live.
    private static func startBreak(
        state: inout PomodoroState,
        planned: Int,
        now: Date,
        overridingCall: Bool,
        settings: Settings,
        log: SessionLogStore,
        library: [Activity],
        rng: inout some RandomNumberGenerator,
        calendar: Calendar
    ) -> [PomodoroEffect] {
        let breakMinutes = BreakLogic.breakDuration(forFocusMinutes: planned)
        let breakSeconds = TimeScale.seconds(ofMinutes: breakMinutes)
        let activity = ActivitySelector.select(
            from: library,
            breakMinutes: breakMinutes,
            now: now,
            recentActivityIDs: log.recentBreakActivityIDs(),
            lastCategory: log.lastBreakCategory(library: library),
            settings: settings,
            calendar: calendar,
            rng: &rng
        ) ?? Self.fallbackActivity

        let deadline = now.addingTimeInterval(TimeInterval(breakSeconds))
        beginPhase(&state, .breakRunning(
            deadline: deadline,
            startedAt: now,
            planned: breakMinutes,
            activity: activity,
            caption: ReminderMessages.lineFor(date: now, calendar: calendar)
        ), seconds: breakSeconds)
        state.breakOverridesCall = overridingCall

        // Media goes quiet first, so the chime lands in silence rather than
        // under the music.
        let pause: [PomodoroEffect] = settings.pauseMediaOnBreak ? [.pauseMedia] : []
        return pause + [
            .playFocusCompleteChime,
            .notify(title: "Focus complete", body: "Step away. The next session needs you fresh.", silent: false),
        ]
    }

    /// A call can begin *during* a break (answered mid-break, or the break
    /// was started manually over one) and still be live when the break ends.
    /// Principle 7 applies to the ending, not just the start: no chime and a
    /// silent notification while the mic is hot. The break still completes
    /// and logs normally; `.presentMainWindow`'s own call gate already
    /// suppresses the window.
    private static func completeBreak(state: inout PomodoroState, now: Date, isOnCall: Bool) -> [PomodoroEffect] {
        guard case .breakRunning(_, let startedAt, let planned, let activity, _) = state.phase else { return [] }
        resetToIdle(&state)
        var effects: [PomodoroEffect] = [
            .stopTicker,
            .logSession(SessionLogEntry(kind: .breakCompleted, from: startedAt, to: now, minutes: planned, activity: activity.id)),
        ]
        if !isOnCall {
            effects.append(.playBreakCompleteChime)
        }
        effects.append(.notify(title: "Break complete", body: "Ready when you are.", silent: isOnCall))
        effects.append(.presentMainWindow)
        return effects
    }

    private static func resetToIdle(_ state: inout PomodoroState) {
        beginPhase(&state, .idle, seconds: 0)
    }

    private static func beginPhase(_ state: inout PomodoroState, _ phase: PomodoroState.Phase, seconds: Int) {
        state.phase = phase
        state.totalSeconds = seconds
        state.remainingSeconds = seconds
        state.breakLockFired = false
        state.breakOverridesCall = false
    }

    /// Last-resort activity if the bundled library failed to load — the
    /// selector only returns nil for an empty library (its filters relax
    /// before running dry). The break must still run either way.
    private static let fallbackActivity = Activity(
        id: "rest",
        name: "Take a break",
        instruction: "Step away from the screen.",
        category: .mindfulness,
        band: .short,
        suitableTimes: Activity.TimeOfDay.allCases
    )
}
