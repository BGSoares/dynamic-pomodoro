import Foundation
import Testing
@testable import DynamicPomodoro

/// Exercises the pure reducer with synthetic dates — no real timers required.
@Suite("PomodoroCore")
final class PomodoroCoreTests {
    private let tempDir: URL
    private let suiteName: String
    private let defaults: UserDefaults
    private let settings: Settings
    private let log: SessionLogStore
    private let library: [Activity]
    private var rng = SystemRandomNumberGenerator()

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PomodoroCoreTests-\(UUID().uuidString)", isDirectory: true)
        log = SessionLogStore(directory: tempDir)
        suiteName = "PomodoroCoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = Settings(defaults: defaults)
        settings.workdayStartMinutes = 9 * 60
        settings.workdayEndMinutes = 18 * 60
        settings.minFocusMinutes = 20
        settings.maxFocusMinutes = 40
        library = [
            Activity(id: "a", name: "Stretch A", instruction: "",
                     category: .stretch, band: .short,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "b", name: "Breathwork B", instruction: "",
                     category: .breathwork, band: .short,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func date(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c)!
    }

    private func reduce(_ state: inout PomodoroState, _ action: PomodoroAction, isOnCall: Bool = false) -> [PomodoroEffect] {
        PomodoroReducer.reduce(&state, action,
                               settings: settings,
                               log: log,
                               library: library,
                               isOnCall: isOnCall,
                               rng: &rng)
    }

    private func contains(_ effects: [PomodoroEffect], notificationTitled title: String) -> Bool {
        effects.contains { if case .notify(let t, _) = $0 { return t == title }; return false }
    }

    private func contains(_ effects: [PomodoroEffect], logOfKind kind: SessionLogEntry.Kind) -> Bool {
        effects.contains { if case .logSession(let entry) = $0 { return entry.kind == kind }; return false }
    }

    private func loggedEntry(in effects: [PomodoroEffect]) -> SessionLogEntry? {
        for e in effects { if case .logSession(let entry) = e { return entry } }
        return nil
    }

    // MARK: - startFocus

    @Test func startFocusFromIdleTransitionsToFocus() throws {
        var state = PomodoroState()
        let now = date(hour: 13)
        let effects = reduce(&state, .startFocus(now: now))

        guard case .focus(let deadline, let startedAt, let planned) = state.phase else {
            Issue.record("Expected .focus, got \(state.phase)")
            return
        }
        #expect(startedAt == now)
        #expect(abs(deadline.timeIntervalSince(now) - TimeInterval(planned * 60)) < 0.001)
        #expect(state.totalSeconds == planned * 60)
        #expect(state.remainingSeconds == planned * 60)
        #expect(!state.breakLockFired)

        // First effect is startTicker; second is a focus-started notification.
        #expect(effects.first == .startTicker)
        #expect(contains(effects, notificationTitled: "Focus started"))
    }

    @Test func startFocusFromFocusIsIgnored() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        let snapshot = state
        let effects = reduce(&state, .startFocus(now: date(hour: 14)))
        #expect(state == snapshot)
        #expect(effects.isEmpty)
    }

    // MARK: - First-session-of-day wiring

    @Test func firstSessionOfDayUsesMinimumDuration() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13, minute: 30)))
        guard case .focus(_, _, let planned) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        // Peak time, but the log is empty — first session forces the minimum.
        #expect(planned == settings.minFocusMinutes)
    }

    @Test func completedFocusTodayUnlocksTheCurve() {
        log.append(SessionLogEntry(kind: .focusCompleted,
                                   from: date(hour: 9), to: date(hour: 9, minute: 20), minutes: 20))
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13, minute: 30)))
        guard case .focus(_, _, let planned) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        // Midpoint of the 9–18 workday → full maximum.
        #expect(planned == settings.maxFocusMinutes)
    }

    @Test func abandonedAttemptDoesNotConsumeTheWarmup() {
        log.append(SessionLogEntry(kind: .focusAbandoned,
                                   from: date(hour: 9), to: date(hour: 9, minute: 1), minutes: 20))
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13, minute: 30)))
        guard case .focus(_, _, let planned) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        // A one-minute false start provides no warm-up: still the day's first.
        #expect(planned == settings.minFocusMinutes)
    }

    // MARK: - abandonFocus

    @Test func abandonFocusLogsAndReturnsToIdle() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        let effects = reduce(&state, .abandonFocus(now: date(hour: 13, minute: 5)))

        #expect(state.phase == .idle)
        #expect(state.remainingSeconds == 0)
        #expect(state.totalSeconds == 0)
        #expect(effects.contains(.stopTicker))
        #expect(contains(effects, logOfKind: .focusAbandoned))
    }

    // MARK: - tick (focus → break)

    @Test func tickAtFocusDeadlineTransitionsToBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))

        guard case .focus(let deadline, _, let planned) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        let effects = reduce(&state, .tick(now: deadline))

        guard case .breakRunning(_, let startedAt, let breakPlanned, _, _) = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(startedAt == deadline)
        #expect(breakPlanned == BreakLogic.breakDuration(forFocusMinutes: planned))

        #expect(effects.contains(.playFocusCompleteChime))
        #expect(contains(effects, logOfKind: .focusCompleted))
        #expect(contains(effects, notificationTitled: "Focus complete"))
        #expect(!state.breakLockFired)
    }

    // MARK: - Missed-deadline grace (sleep across the deadline)

    @Test func tickWithinGraceStillCompletesFocus() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let deadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        // Just inside the grace window: treated as a normal completion.
        let effects = reduce(&state, .tick(now: deadline.addingTimeInterval(PomodoroReducer.missedDeadlineGraceSeconds - 1)))
        guard case .breakRunning = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(contains(effects, logOfKind: .focusCompleted))
    }

    @Test func tickPastGraceAbandonsAtDeadlineWithNoBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let deadline, let startedAt, let planned) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        // Waking long after the deadline: nobody was there. No fabricated
        // completion, no break, no chime, no screen lock.
        let effects = reduce(&state, .tick(now: deadline.addingTimeInterval(PomodoroReducer.missedDeadlineGraceSeconds + 60)))

        #expect(state.phase == .idle)
        #expect(effects.contains(.stopTicker))
        #expect(!effects.contains(.playFocusCompleteChime))
        #expect(!effects.contains(.lockScreen))
        #expect(contains(effects, logOfKind: .focusAbandoned))
        let entry = loggedEntry(in: effects)
        #expect(entry?.startedAt == startedAt)
        #expect(entry?.endedAt == deadline)
        #expect(entry?.plannedMinutes == planned)
    }

    // MARK: - Break deferral while on a call

    /// Reach `.focus` and return its deadline.
    private func startFocusSession(_ state: inout PomodoroState) -> Date {
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let deadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return date(hour: 13)
        }
        return deadline
    }

    @Test func deadlineOnCallDefersTheBreak() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        let effects = reduce(&state, .tick(now: deadline), isOnCall: true)

        guard case .breakPending(let planned, let since) = state.phase else {
            Issue.record("Expected .breakPending, got \(state.phase)")
            return
        }
        #expect(since == deadline)
        #expect(planned == settings.minFocusMinutes)
        // Focus still completed, honestly, at its deadline.
        #expect(contains(effects, logOfKind: .focusCompleted))
        #expect(loggedEntry(in: effects)?.endedAt == deadline)
        // But nothing that would intrude on the call.
        #expect(!effects.contains(.playFocusCompleteChime))
        #expect(!effects.contains(.lockScreen))
        #expect(!effects.contains(.stopTicker))
    }

    @Test func pendingTickStillOnCallDoesNothing() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        _ = reduce(&state, .tick(now: deadline), isOnCall: true)
        let snapshot = state
        let effects = reduce(&state, .tick(now: deadline.addingTimeInterval(60)), isOnCall: true)
        #expect(state == snapshot)
        #expect(effects.isEmpty)
    }

    @Test func pendingStartsBreakOnceCallEnds() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        _ = reduce(&state, .tick(now: deadline), isOnCall: true)
        let callEnd = deadline.addingTimeInterval(300)
        let effects = reduce(&state, .tick(now: callEnd), isOnCall: false)

        guard case .breakRunning(_, let startedAt, let breakPlanned, _, let reminder) = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(startedAt == callEnd)
        #expect(breakPlanned == BreakLogic.breakDuration(forFocusMinutes: settings.minFocusMinutes))
        #expect(reminder != nil)
        #expect(effects.contains(.playFocusCompleteChime))
        // focusCompleted was already logged when the deferral began.
        #expect(!contains(effects, logOfKind: .focusCompleted))
    }

    @Test func pendingPastCapGoesIdleAndLogsSkippedBreak() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        _ = reduce(&state, .tick(now: deadline), isOnCall: true)
        let wayLater = deadline.addingTimeInterval(PomodoroReducer.breakPendingCapSeconds + 60)
        let effects = reduce(&state, .tick(now: wayLater), isOnCall: true)

        #expect(state.phase == .idle)
        #expect(effects.contains(.stopTicker))
        #expect(contains(effects, logOfKind: .breakSkipped))
        #expect(!effects.contains(.playFocusCompleteChime))
    }

    @Test func startPendingBreakOverridesTheCall() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        _ = reduce(&state, .tick(now: deadline), isOnCall: true)
        let effects = reduce(&state, .startPendingBreak(now: deadline.addingTimeInterval(30)), isOnCall: true)

        guard case .breakRunning = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(effects.contains(.playFocusCompleteChime))
    }

    @Test func fastForwardFromFocusOnCallDefersLikeTheRealDeadline() {
        var state = PomodoroState()
        _ = startFocusSession(&state)
        let effects = reduce(&state, .fastForward(now: date(hour: 13, minute: 1)), isOnCall: true)
        guard case .breakPending = state.phase else {
            Issue.record("Expected .breakPending, got \(state.phase)")
            return
        }
        #expect(contains(effects, logOfKind: .focusCompleted))
        #expect(!effects.contains(.playFocusCompleteChime))
    }

    @Test func fastForwardFromPendingStartsBreakDespiteCall() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        _ = reduce(&state, .tick(now: deadline), isOnCall: true)
        _ = reduce(&state, .fastForward(now: deadline.addingTimeInterval(10)), isOnCall: true)
        guard case .breakRunning = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
    }

    @Test func startPendingBreakOutsidePendingIsIgnored() {
        var state = PomodoroState()
        let effects = reduce(&state, .startPendingBreak(now: date(hour: 13)))
        #expect(state.phase == .idle)
        #expect(effects.isEmpty)
    }

    @Test func deadlineNotOnCallBehavesExactlyAsBefore() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        let effects = reduce(&state, .tick(now: deadline), isOnCall: false)
        guard case .breakRunning = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(contains(effects, logOfKind: .focusCompleted))
        #expect(effects.contains(.playFocusCompleteChime))
    }

    @Test func missedDeadlineGraceWinsOverCallDeferral() {
        var state = PomodoroState()
        let deadline = startFocusSession(&state)
        // Asleep way past the deadline AND on a call at wake: absence wins —
        // no pending break, no fabricated completion.
        let effects = reduce(&state, .tick(now: deadline.addingTimeInterval(PomodoroReducer.missedDeadlineGraceSeconds + 60)), isOnCall: true)
        #expect(state.phase == .idle)
        #expect(contains(effects, logOfKind: .focusAbandoned))
    }

    // MARK: - 30s break lock

    @Test func tickAt30SecondsIntoBreakEmitsLockScreenOnce() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        _ = reduce(&state, .tick(now: focusDeadline)) // transition into break
        let breakStart = focusDeadline

        // Tick at 29s — no lock yet.
        let e29 = reduce(&state, .tick(now: breakStart.addingTimeInterval(29)))
        #expect(!e29.contains(.lockScreen))
        #expect(!state.breakLockFired)

        // Tick at exactly 30s — lock fires.
        let e30 = reduce(&state, .tick(now: breakStart.addingTimeInterval(30)))
        #expect(e30.contains(.lockScreen))
        #expect(state.breakLockFired)

        // Tick at 40s — already fired, must not fire again.
        let e40 = reduce(&state, .tick(now: breakStart.addingTimeInterval(40)))
        #expect(!e40.contains(.lockScreen))
        #expect(state.breakLockFired)
    }

    @Test func breakLockNotFiredIfSkippedBefore30s() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        _ = reduce(&state, .tick(now: focusDeadline))
        let breakStart = focusDeadline

        _ = reduce(&state, .tick(now: breakStart.addingTimeInterval(10)))
        let effects = reduce(&state, .skipBreak(now: breakStart.addingTimeInterval(11)))
        #expect(!effects.contains(.lockScreen))
        #expect(!state.breakLockFired)
        #expect(state.phase == .idle)
    }

    // MARK: - skipBreak / completeBreak

    @Test func skipBreakLogsAndReturnsToIdle() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        _ = reduce(&state, .tick(now: focusDeadline))

        let effects = reduce(&state, .skipBreak(now: focusDeadline.addingTimeInterval(60)))
        #expect(state.phase == .idle)
        #expect(effects.contains(.stopTicker))
        #expect(contains(effects, logOfKind: .breakSkipped))
    }

    @Test func tickAtBreakDeadlineCompletesBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            Issue.record("Expected .focus")
            return
        }
        _ = reduce(&state, .tick(now: focusDeadline))

        guard case .breakRunning(let breakDeadline, _, _, _, _) = state.phase else {
            Issue.record("Expected .breakRunning")
            return
        }
        let effects = reduce(&state, .tick(now: breakDeadline))
        #expect(state.phase == .idle)
        #expect(effects.contains(.stopTicker))
        #expect(effects.contains(.playBreakCompleteChime))
        #expect(contains(effects, logOfKind: .breakCompleted))
    }

    // MARK: - fastForward

    @Test func fastForwardFromFocusCompletesIntoBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        let effects = reduce(&state, .fastForward(now: date(hour: 13, minute: 1)))

        guard case .breakRunning = state.phase else {
            Issue.record("Expected .breakRunning, got \(state.phase)")
            return
        }
        #expect(contains(effects, logOfKind: .focusCompleted))
        #expect(effects.contains(.playFocusCompleteChime))
    }

    @Test func fastForwardFromBreakCompletesToIdle() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        _ = reduce(&state, .fastForward(now: date(hour: 13, minute: 1)))
        let effects = reduce(&state, .fastForward(now: date(hour: 13, minute: 2)))

        #expect(state.phase == .idle)
        #expect(contains(effects, logOfKind: .breakCompleted))
        #expect(effects.contains(.stopTicker))
    }

    @Test func fastForwardFromIdleDoesNothing() {
        var state = PomodoroState()
        let effects = reduce(&state, .fastForward(now: date(hour: 13)))
        #expect(state.phase == .idle)
        #expect(effects.isEmpty)
    }
}
