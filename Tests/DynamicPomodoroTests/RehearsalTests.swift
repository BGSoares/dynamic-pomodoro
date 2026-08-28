import Foundation
import Testing
@testable import DynamicPomodoro

/// The pre-ship gate, as tests: whole simulated days played through the real
/// logic, checked against the invariants (PURPOSE's promises) while they run.
/// A finding here is a bug the user would have met on screen.
@Suite("Rehearsal")
struct RehearsalTests {

    // MARK: - Invariant sweep

    @Test func canonicalDayIsClean() {
        let result = DayRehearsal.run(script: .canonical)
        #expect(result.findings.isEmpty, "\(result.findings)")
    }

    @Test func meetingsDayIsClean() {
        let result = DayRehearsal.run(script: .meetings)
        #expect(result.findings.isEmpty, "\(result.findings)")
    }

    /// Thirty differently seeded restless days — late starts, skips,
    /// abandons, lid-closes, calls in odd places — all clean.
    @Test(arguments: UInt64(1)...30)
    func restlessDayIsClean(seed: UInt64) {
        let result = DayRehearsal.run(script: .restless(seed: seed), seed: seed)
        #expect(result.findings.isEmpty, "seed \(seed): \(result.findings)")
    }

    // MARK: - Determinism (what makes transcripts diffable and bugs replayable)

    @Test func sameScriptAndSeedReplaysIdentically() {
        let a = DayRehearsal.run(script: .restless(seed: 7), seed: 7)
        let b = DayRehearsal.run(script: .restless(seed: 7), seed: 7)
        #expect(a.renderedTranscript() == b.renderedTranscript())
    }

    // MARK: - Structural coverage
    //
    // The scripted days exist to exercise specific flows. Timing drift (a
    // curve change, a persona change) could quietly turn "the call swallows
    // a deadline" into "the call lands between sessions" and the coverage
    // would rot with the transcript still green — these assertions make that
    // rot loud. If one fails after an intentional behaviour change, re-tune
    // the script's call windows to the new rhythm (see RehearsalScript).

    @Test func canonicalDayCoversTheCoreLoop() {
        let result = DayRehearsal.run(script: .canonical)
        let completed = result.entries.filter { $0.kind == .focusCompleted }.count
        let skipped = result.entries.filter { $0.kind == .breakSkipped }
        #expect(completed >= 10, "a full 9h day should hold a full loop, got \(completed) sessions")
        #expect(skipped.count == 1 && skipped[0].activityID != nil,
                "exactly one hold-to-skip of a running break")
        #expect(result.events.contains { $0.text.contains("the countdown fires") },
                "the unlock auto-start countdown should fire at least once")
        #expect(result.events.contains { $0.detail.contains(where: { $0.hasPrefix("nudge:") }) },
                "the first card at/after 16:20 should carry the nudge")
    }

    @Test func meetingsDayCoversAllThreeCallOutcomes() {
        let result = DayRehearsal.run(script: .meetings)

        // 1. A pending break overridden by hand.
        #expect(result.events.contains { $0.text.contains("Start break now") && $0.kind == .user },
                "the user should override one pending break")

        // 2. A pending break that starts on its own when the call ends: its
        // card goes up well after the focus that earned it ended.
        let deferredBreak = result.entries.contains { entry in
            guard entry.kind == .breakCompleted, entry.activityID != nil else { return false }
            guard let focus = result.entries.last(where: {
                $0.kind == .focusCompleted && $0.endedAt <= entry.startedAt
            }) else { return false }
            return entry.startedAt.timeIntervalSince(focus.endedAt) > 120
        }
        #expect(deferredBreak, "one owed break should start by itself at a call's end")

        // 3. A pending break the 30-minute cap wrote off: skipped, no card
        // ever shown (nil activity), after a full cap-length wait.
        let capped = result.entries.first { $0.kind == .breakSkipped && $0.activityID == nil }
        #expect(capped != nil, "the long call should cap one owed break out")
        if let capped {
            #expect(capped.endedAt.timeIntervalSince(capped.startedAt)
                    >= PomodoroReducer.breakPendingCapSeconds)
        }
    }

    /// Principle 7, pinned at the reducer level as well: what the app says
    /// while a call is live, it says silently.
    @Test func everySoundTheAppMakesDuringACallWasAskedFor() {
        for seed in UInt64(1)...30 {
            let result = DayRehearsal.run(script: .restless(seed: seed), seed: seed)
            #expect(result.findings.allSatisfy { !$0.contains("principle 7") },
                    "seed \(seed): \(result.findings)")
        }
    }
}
