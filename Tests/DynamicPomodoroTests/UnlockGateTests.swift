import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("UnlockGate")
struct UnlockGateTests {
    private let breakEnd = Date(timeIntervalSince1970: 1_000_000)

    private let sampleActivity = Activity(
        id: "a", name: "Stretch", instruction: "",
        category: .stretch, band: .short, suitableTimes: Activity.TimeOfDay.allCases
    )

    // MARK: - shouldOffer

    @Test func offersWhenIdleAndFresh() {
        let now = breakEnd.addingTimeInterval(5 * 60)
        #expect(UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))
    }

    @Test func refusesWhenNotIdle() {
        let now = breakEnd.addingTimeInterval(5 * 60)

        let focusPhase = PomodoroState.Phase.focus(
            deadline: now.addingTimeInterval(20 * 60), startedAt: now, planned: 20
        )
        #expect(!UnlockGate.shouldOffer(
            phase: focusPhase, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))

        let pendingPhase = PomodoroState.Phase.breakPending(planned: 20, since: now)
        #expect(!UnlockGate.shouldOffer(
            phase: pendingPhase, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))

        let runningPhase = PomodoroState.Phase.breakRunning(
            deadline: now.addingTimeInterval(5 * 60), startedAt: now, planned: 20,
            activity: sampleActivity, caption: nil
        )
        #expect(!UnlockGate.shouldOffer(
            phase: runningPhase, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))
    }

    @Test func refusesWhenNoBreakEndLogged() {
        #expect(!UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: nil, suppressedBreakEnd: nil,
            now: breakEnd, windowMinutes: 20
        ))
    }

    @Test func refusesWhenSuppressedForThisBreakEnd() {
        let now = breakEnd.addingTimeInterval(5 * 60)
        #expect(!UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: breakEnd, suppressedBreakEnd: breakEnd,
            now: now, windowMinutes: 20
        ))
    }

    @Test func offersAgainAfterADifferentBreakEnd() {
        // A cancelled offer only suppresses its own break end — a fresh
        // cycle produces a new break end, which naturally re-arms the offer.
        let laterBreakEnd = breakEnd.addingTimeInterval(3600)
        let now = laterBreakEnd.addingTimeInterval(60)
        #expect(UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: laterBreakEnd, suppressedBreakEnd: breakEnd,
            now: now, windowMinutes: 20
        ))
    }

    @Test func refusesOutsideTheStalenessWindow() {
        let now = breakEnd.addingTimeInterval(21 * 60)
        #expect(!UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))
    }

    @Test func offersExactlyAtTheWindowBoundary() {
        let now = breakEnd.addingTimeInterval(20 * 60)
        #expect(UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))
    }

    @Test func refusesOnNegativeElapsed() {
        // Clock skew or a bogus "unlock in the past" must never read as fresh.
        let now = breakEnd.addingTimeInterval(-60)
        #expect(!UnlockGate.shouldOffer(
            phase: .idle, lastBreakEnd: breakEnd, suppressedBreakEnd: nil,
            now: now, windowMinutes: 20
        ))
    }

    // MARK: - shouldStillFire

    @Test func stillFiresWithinGrace() {
        let deadline = Date(timeIntervalSince1970: 2_000_000)
        #expect(UnlockGate.shouldStillFire(deadline: deadline, now: deadline))
        #expect(UnlockGate.shouldStillFire(deadline: deadline, now: deadline.addingTimeInterval(2)))
        #expect(UnlockGate.shouldStillFire(deadline: deadline, now: deadline.addingTimeInterval(-5)))
    }

    @Test func stillFiresExactlyAtTheGraceBoundary() {
        let deadline = Date(timeIntervalSince1970: 2_000_000)
        #expect(UnlockGate.shouldStillFire(deadline: deadline, now: deadline.addingTimeInterval(3)))
    }

    @Test func doesNotFireAfterOvershootingGrace() {
        let deadline = Date(timeIntervalSince1970: 2_000_000)
        #expect(!UnlockGate.shouldStillFire(deadline: deadline, now: deadline.addingTimeInterval(3.01)))
    }
}
