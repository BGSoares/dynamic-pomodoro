import Foundation

/// Pure-Swift state machine. No AppKit, no Combine — every transition is exercised
/// with a synthetic Date, so tests need no real timers. Effects are returned as values
/// for `TimerEngine` to interpret.

// MARK: - State

struct PomodoroState: Equatable {
    enum Phase: Equatable {
        case idle
        case focus(deadline: Date, startedAt: Date, planned: Int)
        case breakRunning(
            deadline: Date,
            startedAt: Date,
            planned: Int,
            activity: Activity,
            reminder: String?
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
}

extension PomodoroState.Phase {
    /// Integer discriminator that ignores associated values — used to
    /// deduplicate phase-change events that differ only in deadline/activity data.
    var tag: Int {
        switch self { case .idle: 0; case .focus: 1; case .breakRunning: 2 }
    }
}

extension PomodoroState {
    private var breakInfo: (activity: Activity, reminder: String?)? {
        if case .breakRunning(_, _, _, let a, let r) = phase { return (a, r) }
        return nil
    }

    var currentActivity: Activity? { breakInfo?.activity }
    var currentReminderMessage: String? { breakInfo?.reminder }

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
    case tick(now: Date)
    case fastForward(now: Date)
}

// MARK: - Effect

enum PomodoroEffect: Equatable {
    case notify(title: String, body: String)
    case logSession(SessionLogEntry)
    case playFocusCompleteChime
    case playBreakCompleteChime
    case startTicker
    case stopTicker
    case lockScreen
}

// MARK: - Reducer

enum PomodoroReducer {
    /// Seconds after a break starts before the screen auto-locks.
    /// Long enough to read the activity card; short enough that walking away
    /// without the lock would be a security risk.
    static let breakLockDelaySeconds: TimeInterval = 30

    static func reduce(
        _ state: inout PomodoroState,
        _ action: PomodoroAction,
        settings: Settings,
        log: SessionLogStore,
        library: [Activity],
        rng: inout SystemRandomNumberGenerator
    ) -> [PomodoroEffect] {
        switch action {
        case .startFocus(let now):
            // Re-entrant starts are ignored — once running, you finish or abandon.
            guard case .idle = state.phase else { return [] }
            let minutes = DurationCurve.focusDuration(
                now: now,
                isFirstSessionOfDay: !log.hasEntryToday(now: now),
                settings: settings
            )
            let deadline = now.addingTimeInterval(TimeInterval(minutes * 60))
            state.phase = .focus(deadline: deadline, startedAt: now, planned: minutes)
            state.totalSeconds = minutes * 60
            state.remainingSeconds = state.totalSeconds
            state.breakLockFired = false
            return [
                .startTicker,
                .notify(title: "Focus started", body: "\(minutes) min."),
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
            return [
                .stopTicker,
                .logSession(SessionLogEntry(kind: .breakSkipped, from: startedAt, to: now, minutes: planned, activity: activity.id)),
            ]

        case .tick(let now):
            switch state.phase {
            case .idle:
                return [.stopTicker]

            case .focus(let deadline, _, _):
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
                state.remainingSeconds = remaining
                if remaining == 0 {
                    return completeFocus(state: &state, now: now, settings: settings, log: log, library: library, rng: &rng)
                }
                return []

            case .breakRunning(let deadline, let startedAt, _, _, _):
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
                state.remainingSeconds = remaining
                if remaining == 0 {
                    return completeBreak(state: &state, now: now)
                }
                if !state.breakLockFired,
                   now.timeIntervalSince(startedAt) >= breakLockDelaySeconds {
                    state.breakLockFired = true
                    return [.lockScreen]
                }
                return []
            }

        case .fastForward(let now):
            switch state.phase {
            case .focus:
                return completeFocus(state: &state, now: now, settings: settings, log: log, library: library, rng: &rng)
            case .breakRunning:
                return completeBreak(state: &state, now: now)
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
        rng: inout SystemRandomNumberGenerator
    ) -> [PomodoroEffect] {
        guard case .focus(_, let startedAt, let planned) = state.phase else { return [] }

        let breakMinutes = BreakLogic.breakDuration(forFocusMinutes: planned)
        let activity = ActivitySelector.select(
            from: library,
            breakMinutes: breakMinutes,
            now: now,
            recentActivityIDs: log.recentBreakActivityIDs(),
            lastCategory: log.lastBreakCategory(library: library),
            settings: settings,
            rng: &rng
        ) ?? Self.fallbackActivity

        let deadline = now.addingTimeInterval(TimeInterval(breakMinutes * 60))
        let reminderLine = ReminderMessages.lineFor(date: now)
        state.phase = .breakRunning(
            deadline: deadline,
            startedAt: now,
            planned: breakMinutes,
            activity: activity,
            reminder: reminderLine.isEmpty ? nil : reminderLine
        )
        state.totalSeconds = breakMinutes * 60
        state.remainingSeconds = state.totalSeconds
        state.breakLockFired = false

        return [
            .logSession(SessionLogEntry(kind: .focusCompleted, from: startedAt, to: now, minutes: planned)),
            .playFocusCompleteChime,
            .notify(title: "Focus complete", body: "Step away. The next session needs you fresh."),
        ]
    }

    private static func completeBreak(state: inout PomodoroState, now: Date) -> [PomodoroEffect] {
        guard case .breakRunning(_, let startedAt, let planned, let activity, _) = state.phase else { return [] }
        resetToIdle(&state)
        return [
            .stopTicker,
            .logSession(SessionLogEntry(kind: .breakCompleted, from: startedAt, to: now, minutes: planned, activity: activity.id)),
            .playBreakCompleteChime,
            .notify(title: "Break complete", body: "Ready when you are."),
        ]
    }

    private static func resetToIdle(_ state: inout PomodoroState) {
        state.phase = .idle
        state.remainingSeconds = 0
        state.totalSeconds = 0
        state.breakLockFired = false
    }

    /// Last-resort activity when no library entry matches the current band/time-of-day.
    /// The break must still run — the user still needs to step away.
    private static let fallbackActivity = Activity(
        id: "rest",
        name: "Take a break",
        instruction: "Step away from the screen.",
        category: .mindfulness,
        band: .short,
        suitableTimes: Activity.TimeOfDay.allCases
    )
}
