import XCTest
@testable import DynamicPomodoro

/// Exercises the pure reducer with synthetic dates — no real timers required.
@MainActor
final class PomodoroCoreTests: XCTestCase {
    private var log: SessionLogStore!
    private var tempDir: URL!
    private var settings: Settings!
    private var library: [Activity]!
    private var rng = SystemRandomNumberGenerator()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PomodoroCoreTests-\(UUID().uuidString)", isDirectory: true)
        log = SessionLogStore(directory: tempDir)
        settings = Settings.shared
        settings.workdayStartMinutes = 9 * 60
        settings.workdayEndMinutes = 18 * 60
        settings.minFocusMinutes = 20
        settings.maxFocusMinutes = 40
        library = [
            Activity(id: "a", name: "Stretch A", instruction: "",
                     category: .stretch, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
            Activity(id: "b", name: "Breathwork B", instruction: "",
                     category: .breathwork, band: .short, energy: .gentle,
                     suitableTimes: [.morning, .midday, .afternoon, .endOfDay]),
        ]
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func date(hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute; c.second = second
        return Calendar.current.date(from: c)!
    }

    private func reduce(_ state: inout PomodoroState, _ action: PomodoroAction) -> [PomodoroEffect] {
        PomodoroReducer.reduce(&state, action,
                               settings: settings,
                               log: log,
                               library: library,
                               rng: &rng)
    }

    // MARK: - startFocus

    func testStartFocusFromIdleTransitionsToFocus() {
        var state = PomodoroState()
        let now = date(hour: 13)
        let effects = reduce(&state, .startFocus(now: now))

        guard case .focus(let deadline, let startedAt, let planned) = state.phase else {
            return XCTFail("Expected .focus, got \(state.phase)")
        }
        XCTAssertEqual(startedAt, now)
        XCTAssertEqual(deadline.timeIntervalSince(now), TimeInterval(planned * 60), accuracy: 0.001)
        XCTAssertEqual(state.totalSeconds, planned * 60)
        XCTAssertEqual(state.remainingSeconds, planned * 60)
        XCTAssertFalse(state.breakLockFired)

        // First effect is startTicker; second is a focus-started notification.
        XCTAssertEqual(effects.first, .startTicker)
        XCTAssertTrue(effects.contains(where: {
            if case .notify(let title, _) = $0 { return title == "Focus started" }
            return false
        }))
    }

    func testStartFocusFromFocusIsIgnored() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        let snapshot = state
        let effects = reduce(&state, .startFocus(now: date(hour: 14)))
        XCTAssertEqual(state, snapshot)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - abandonFocus

    func testAbandonFocusLogsAndReturnsToIdle() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        let effects = reduce(&state, .abandonFocus(now: date(hour: 13, minute: 5)))

        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.remainingSeconds, 0)
        XCTAssertEqual(state.totalSeconds, 0)
        XCTAssertTrue(effects.contains(.stopTicker))
        XCTAssertTrue(effects.contains(where: {
            if case .logSession(let entry) = $0 { return entry.kind == .focusAbandoned }
            return false
        }))
    }

    // MARK: - tick (focus → break)

    func testTickAtFocusDeadlineTransitionsToBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))

        guard case .focus(let deadline, _, let planned) = state.phase else {
            return XCTFail("Expected .focus")
        }
        let effects = reduce(&state, .tick(now: deadline))

        guard case .breakRunning(_, let startedAt, let breakPlanned, _, _) = state.phase else {
            return XCTFail("Expected .breakRunning, got \(state.phase)")
        }
        XCTAssertEqual(startedAt, deadline)
        XCTAssertEqual(breakPlanned, BreakLogic.breakDuration(forFocusMinutes: planned))

        XCTAssertTrue(effects.contains(.playFocusCompleteChime))
        XCTAssertTrue(effects.contains(where: {
            if case .logSession(let entry) = $0 { return entry.kind == .focusCompleted }
            return false
        }))
        XCTAssertTrue(effects.contains(where: {
            if case .notify(let title, _) = $0 { return title == "Focus complete" }
            return false
        }))
        XCTAssertFalse(state.breakLockFired)
    }

    // MARK: - 15s break lock

    func testTickAt15SecondsIntoBreakEmitsLockScreenOnce() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            return XCTFail("Expected .focus")
        }
        _ = reduce(&state, .tick(now: focusDeadline)) // transition into break
        let breakStart = focusDeadline

        // Tick at 14s — no lock yet.
        let e14 = reduce(&state, .tick(now: breakStart.addingTimeInterval(14)))
        XCTAssertFalse(e14.contains(.lockScreen))
        XCTAssertFalse(state.breakLockFired)

        // Tick at exactly 15s — lock fires.
        let e15 = reduce(&state, .tick(now: breakStart.addingTimeInterval(15)))
        XCTAssertTrue(e15.contains(.lockScreen))
        XCTAssertTrue(state.breakLockFired)

        // Tick at 20s — already fired, must not fire again.
        let e20 = reduce(&state, .tick(now: breakStart.addingTimeInterval(20)))
        XCTAssertFalse(e20.contains(.lockScreen))
        XCTAssertTrue(state.breakLockFired)
    }

    func testBreakLockNotFiredIfSkippedBefore15s() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            return XCTFail("Expected .focus")
        }
        _ = reduce(&state, .tick(now: focusDeadline))
        let breakStart = focusDeadline

        _ = reduce(&state, .tick(now: breakStart.addingTimeInterval(10)))
        let effects = reduce(&state, .skipBreak(now: breakStart.addingTimeInterval(11)))
        XCTAssertFalse(effects.contains(.lockScreen))
        XCTAssertFalse(state.breakLockFired)
        XCTAssertEqual(state.phase, .idle)
    }

    // MARK: - skipBreak / completeBreak

    func testSkipBreakLogsAndReturnsToIdle() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            return XCTFail("Expected .focus")
        }
        _ = reduce(&state, .tick(now: focusDeadline))

        let effects = reduce(&state, .skipBreak(now: focusDeadline.addingTimeInterval(60)))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(effects.contains(.stopTicker))
        XCTAssertTrue(effects.contains(where: {
            if case .logSession(let entry) = $0 { return entry.kind == .breakSkipped }
            return false
        }))
    }

    func testTickAtBreakDeadlineCompletesBreak() {
        var state = PomodoroState()
        _ = reduce(&state, .startFocus(now: date(hour: 13)))
        guard case .focus(let focusDeadline, _, _) = state.phase else {
            return XCTFail("Expected .focus")
        }
        _ = reduce(&state, .tick(now: focusDeadline))

        guard case .breakRunning(let breakDeadline, _, _, _, _) = state.phase else {
            return XCTFail("Expected .breakRunning")
        }
        let effects = reduce(&state, .tick(now: breakDeadline))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(effects.contains(.stopTicker))
        XCTAssertTrue(effects.contains(.playBreakCompleteChime))
        XCTAssertTrue(effects.contains(where: {
            if case .logSession(let entry) = $0 { return entry.kind == .breakCompleted }
            return false
        }))
    }
}
