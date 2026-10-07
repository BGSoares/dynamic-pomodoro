import Foundation
import Testing
@testable import DynamicPomodoro

@Suite("UnlockGate")
struct UnlockGateTests {
    private let lastEnd = Date(timeIntervalSince1970: 1_000_000)
    private let window = 120

    private let sampleActivity = Activity(
        id: "a", name: "Stretch", instruction: "",
        category: .stretch, band: .short, suitableTimes: Activity.TimeOfDay.allCases
    )

    private func offers(_ phase: PomodoroState.Phase = .idle, lastEnd: Date?, minutesLater: Double) -> Bool {
        UnlockGate.shouldOffer(
            phase: phase, lastActivityEnd: lastEnd,
            now: self.lastEnd.addingTimeInterval(minutesLater * 60), windowMinutes: window
        )
    }

    // MARK: - shouldOffer

    @Test func offersWhenIdleAndRecent() {
        #expect(offers(lastEnd: lastEnd, minutesLater: 5))
    }

    @Test func offersEveryTimeItIsAsked() {
        // No memory of earlier offers: a cancel means "not now", so the next
        // unlock in the window gets the countdown again.
        #expect(offers(lastEnd: lastEnd, minutesLater: 5))
        #expect(offers(lastEnd: lastEnd, minutesLater: 40))
    }

    @Test func refusesWhenNotIdle() {
        let now = lastEnd.addingTimeInterval(5 * 60)
        let focusPhase = PomodoroState.Phase.focus(
            deadline: now.addingTimeInterval(20 * 60), startedAt: now, planned: 20
        )
        let pendingPhase = PomodoroState.Phase.breakPending(planned: 20, since: now)
        let runningPhase = PomodoroState.Phase.breakRunning(
            deadline: now.addingTimeInterval(5 * 60), startedAt: now, planned: 20,
            activity: sampleActivity, caption: nil
        )
        for phase in [focusPhase, pendingPhase, runningPhase] {
            #expect(!offers(phase, lastEnd: lastEnd, minutesLater: 5))
        }
    }

    @Test func refusesWhenNothingWasEverLogged() {
        #expect(!offers(lastEnd: nil, minutesLater: 5))
    }

    @Test func offersExactlyAtTheWindowBoundary() {
        #expect(offers(lastEnd: lastEnd, minutesLater: 120))
    }

    @Test func refusesOutsideTheWindow() {
        #expect(!offers(lastEnd: lastEnd, minutesLater: 120.1))
    }

    @Test func refusesOnNegativeElapsed() {
        // Clock skew or a bogus "unlock in the past" must never read as recent.
        #expect(!offers(lastEnd: lastEnd, minutesLater: -1))
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
