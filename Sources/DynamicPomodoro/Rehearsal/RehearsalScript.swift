import Foundation

/// A day to rehearse: the settings it runs under, what the world does
/// (calls, sleep), and how the simulated user behaves. Two kinds exist:
///
/// - The two *scripted* days (`canonical`, `meetings`) are fully
///   deterministic and back the golden transcripts: any change to what the
///   user would see shows up as a reviewable diff against the checked-in
///   fixture.
/// - The *restless* day is seeded-random: the persona starts late, skips
///   breaks, abandons sessions, sleeps the lid, takes calls — different
///   every seed, so the invariant sweep in the tests walks many differently
///   shaped days through the same rules.
struct RehearsalScript {
    struct TimedOp {
        enum Trigger {
            /// Wall clock, minutes+seconds since midnight.
            case at(minute: Int, second: Int)
            /// The nth break card of the day appearing (1-based).
            case breakStarted(ordinal: Int)
            /// The break has been owed (pending behind a call) this long.
            case pendingFor(seconds: Int)
            /// The nth auto-start countdown HUD of the day (1-based).
            case countdownStarted(ordinal: Int)
        }

        enum Op {
            /// Press and hold the skip button for the full 15 seconds.
            case holdSkip
            /// "Start break now" from the dolphin menu (the pending escape valve).
            case startBreakNow
            /// Abandon the running focus session (confirming the dialog).
            case abandonFocus
            /// Esc, or a click on the countdown HUD (the same cancel).
            case cancelCountdown
            /// Close the lid; the machine sleeps until the given minute.
            case machineSleep(untilMinute: Int)
        }

        let trigger: Trigger
        let op: Op
    }

    var name: String
    var summary: String

    /// The rehearsed date (in the rehearsal's own fixed calendar).
    var year = 2026, month = 1, day = 14

    // The five real settings. The two unexposed countdown timings are
    // rehearsed at the defaults the app ships with.
    var workdayStartMinutes = 9 * 60
    var workdayEndMinutes = 18 * 60
    var minFocusStartMinutes = 20
    var minFocusEndMinutes = 20
    var maxFocusMinutes = 40

    /// Call windows (mic live), minutes since midnight.
    var calls: [ClosedRange<Int>] = []

    /// Think-time before clicking Start when idle at the desk, seconds.
    var startDelaySeconds = 120
    /// When the persona comes back and unlocks, relative to the break's
    /// scheduled end (seconds; negative = back before the chime). Cycled
    /// per lock so one day exercises both the window-presents path (back
    /// early) and the unlock-countdown path (back late).
    var unlockOffsetsFromBreakEnd: [Int] = [-60, 90]
    /// No new sessions at or after this minute — the day is winding down.
    var lastStartMinute = 17 * 60 + 30

    var ops: [TimedOp] = []

    // MARK: - The library of days

    /// An ordinary good day: sessions all day, every break taken but one
    /// mid-afternoon skip (which offers the auto-start countdown and lets
    /// it fire), back early from some breaks and late from others. Runs on
    /// the asymmetric curve the user actually works to – the afternoon
    /// tapers to a 30-minute floor rather than back down to 20 – so the
    /// golden transcript shows the late sessions at the length they really
    /// get.
    static let canonical = RehearsalScript(
        name: "canonical",
        summary: "an ordinary day — every break taken, one afternoon skip, countdown fires",
        minFocusEndMinutes: 30,
        ops: [
            TimedOp(trigger: .breakStarted(ordinal: 5), op: .holdSkip),
        ]
    )

    /// A meeting-shaped day, hitting all three call-vs-break outcomes: the
    /// late-morning call swallows a deadline and the user overrides it with
    /// "Start break now"; the lunchtime call swallows one and the owed break
    /// starts on its own the moment the call ends; the long late-afternoon
    /// call outlives the 30-minute pending cap and the break is honestly
    /// logged as skipped. Call windows are tuned to this script's (fully
    /// deterministic) session rhythm — the structural assertions in
    /// RehearsalTests fail loudly if a logic change moves a deadline out of
    /// its call, so the coverage can't rot silently.
    static let meetings = RehearsalScript(
        name: "meetings",
        summary: "calls everywhere — a manual override, a deferred break, a capped-out break",
        calls: [
            (11 * 60 + 5)...(11 * 60 + 45),      // catches a deadline; user overrides at +2 min
            (12 * 60 + 10)...(12 * 60 + 35),     // catches a deadline; break auto-starts at call end
            (16 * 60 + 15)...(17 * 60 + 25),     // catches a deadline and outlives the pending cap
        ],
        unlockOffsetsFromBreakEnd: [-60],
        ops: [
            // Spends itself on the day's first pending break (the 11:05 call).
            TimedOp(trigger: .pendingFor(seconds: 120), op: .startBreakNow),
        ]
    )

    /// Seeded-random persona for the invariant sweep. Not used for goldens.
    static func restless(seed: UInt64) -> RehearsalScript {
        var rng = SeededRNG(seed: seed)
        var script = RehearsalScript(
            name: "restless-\(seed)",
            summary: "seeded persona — late starts, skips, abandons, calls, a lid-close"
        )
        script.startDelaySeconds = Int.random(in: 20...600, using: &rng)
        script.unlockOffsetsFromBreakEnd = (0..<4).map { _ in Int.random(in: -150...240, using: &rng) }

        // 0–3 calls scattered through the day, 5–50 minutes each.
        for _ in 0..<Int.random(in: 0...3, using: &rng) {
            let start = Int.random(in: (9 * 60 + 30)...(16 * 60 + 30), using: &rng)
            let length = Int.random(in: 5...50, using: &rng)
            script.calls.append(start...(start + length))
        }

        // A couple of impulsive moves.
        if Bool.random(using: &rng) {
            script.ops.append(TimedOp(
                trigger: .breakStarted(ordinal: Int.random(in: 1...4, using: &rng)),
                op: .holdSkip
            ))
        }
        if Double.random(in: 0...1, using: &rng) < 0.4 {
            let minute = Int.random(in: (10 * 60)...(16 * 60), using: &rng)
            script.ops.append(TimedOp(trigger: .at(minute: minute, second: 30), op: .abandonFocus))
        }
        if Double.random(in: 0...1, using: &rng) < 0.4 {
            let minute = Int.random(in: (12 * 60)...(15 * 60), using: &rng)
            let sleepMinutes = Int.random(in: 5...45, using: &rng)
            script.ops.append(TimedOp(
                trigger: .at(minute: minute, second: 0),
                op: .machineSleep(untilMinute: minute + sleepMinutes)
            ))
        }
        if Bool.random(using: &rng) {
            script.ops.append(TimedOp(
                trigger: .countdownStarted(ordinal: 1),
                op: .cancelCountdown
            ))
        }
        // The end-of-day floor wanders either side of the start floor, so
        // the sweep plays days that taper, days that don't, and days that
        // end longer than they began.
        script.minFocusEndMinutes = Int.random(in: 15...35, using: &rng)
        return script
    }
}
