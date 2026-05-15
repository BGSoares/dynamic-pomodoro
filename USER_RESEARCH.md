# User Research

_Single user. Personal tool. Mac only._

## Usage data

No session or feedback data available in this environment (dev machine, no `~/Library/Application Support/DynamicPomodoro/`). The app has not yet triggered the feedback survey — gate is 5 completed focus sessions.

## What we know (from code + commit history)

- The core loop (focus → full-screen break → focus) is working and intentional.
- Screen lock fires 15 seconds into every break. Unconditional — toggle removed in the reducer collapse (commit 3589d0d). Justified in PURPOSE.md: friction belongs here.
- Break activities: 40 entries across 7 categories. Cycling-themed inspiration category is load-bearing per PURPOSE.md §7.
- Hold-to-skip (15s) is core friction, not a lockout.

## Active feedback question (Q2, rev 2)

"Do the breaks actually help you refocus?" — multiple choice: Yes, consistently / Usually / Sometimes / Rarely. Direct measure of the core value proposition. No responses yet.

## Feature status

| Feature | Status |
|---|---|
| Dynamic focus curve | Load-bearing |
| Break activity library | Load-bearing |
| Full-screen overlay + screen lock | Load-bearing |
| Hold-to-skip friction | Load-bearing |
| Skip nudge messages (pool of 5) | Presumed load-bearing; no data |
| Reminder messages (pool of 26, daily rotation) | Presumed load-bearing; no data |
| Daily stats footer | Load-bearing |
| One-shot feedback survey | Active; awaiting first response |

## Next

Read `~/Library/Application Support/DynamicPomodoro/feedback.json` and `sessions.json` once available to validate feature utility and curve calibration.
