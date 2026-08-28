---
description: Rehearse the app's full day and run every check that must pass before a change ships
---

Run the pre-ship validation for the current state of the tree, and read what it produces — the point is not the exit codes, it is that *you watch the user's day before the user has it* (PURPOSE principle 9).

## The gate

1. **`swift test`** — the whole suite: unit tests, thirty-plus rehearsed days checked against the invariants, and the two golden transcripts. Runs on macOS and on Linux (agent environments build the pure core; that is where every user-visible decision lives).
2. **`swift run rehearse all --quiet`** — both scripted days plus a 20-seed sweep of restless days (on macOS: `swift run DynamicPomodoro rehearse all --quiet`). Exit 0 means every day was clean; findings print with timestamps and are bugs the user would have met.
3. **If your change touches anything user-visible** — a string, a duration, a selection rule, a transition — run `swift run rehearse canonical` (and `meetings` if calls are involved) and *read the transcript*. Does the day read right? Then re-record the goldens (`DP_REHEARSAL_RECORD=1 swift test --filter GoldenDayTests`) and read the fixture diff end to end before committing it; the diff is the review artifact and ships in the PR.
4. **If your change touches the AppKit glue** (`main.swift`, `TimerEngine`, `AutoStartService`, `BreakOverlayManager`, `ScreenLockMonitor`) — update the corresponding mirror in `Rehearsal/DayRehearsal.swift` (each mirror is labeled with the file it mirrors), then redo steps 1–3. A mirror that drifts from its glue vouches for an app that no longer exists.
5. **macOS CI must go green** — Views/ and Services/ only compile there. From a Linux environment, push and watch the run rather than declaring victory early.

## When something fails

- An **invariant finding** names a moment and a broken promise. Re-run that exact day (`swift run rehearse restless --seed N`, or the named script) and read the transcript around the timestamp — the reproduction is deterministic.
- A **golden mismatch** is either a regression (fix the code) or an intentional change (re-record, read the diff, say in the commit what changed on screen and why). Never re-record to make a red test go away without reading what moved.
- A **structural coverage failure** in `RehearsalTests` means a scripted day degenerated — a call window no longer catches a deadline. Re-tune the script's call windows to the new rhythm; the transcript shows where the deadlines now land.

## Watching it for real (optional, macOS only)

`DP_SECONDS_PER_MINUTE=2 swift run` compresses prescribed minutes to seconds — a whole focus → break → focus loop, with the real overlay, chimes and screen lock, in about a minute. Debug-only; persistence auto-redirects to a scratch directory so fabricated sessions never touch the real log.
