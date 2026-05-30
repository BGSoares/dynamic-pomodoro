# User Research

_Single user. Personal tool. Mac only._

## Usage data

No session or feedback data available (remote container, no `~/Library/Application Support/DynamicPomodoro/`). Logging is well-instrumented — `sessions.json` and `feedback.json` accumulate on the user's machine. Feedback gate requires 5 completed focus sessions; not yet triggered. _(Weekly review 2026-05-30: no new data. Skip-time is inferrable from existing log fields once data is readable: `endedAt − startedAt` vs `plannedMinutes`.)_

## Active feedback question (Q2, rev 2)

"Do the breaks actually help you refocus?" — multiple choice: Yes, consistently / Usually / Sometimes / Rarely. Measures core value proposition. No responses yet.

## Active thumbs probe

**Reminder quotes** — 👍/👎 widget on `IdleView` after first completed break (once, gated by `reminderMsgThumb` in UserDefaults). Asks whether the short italic lines on the break screen feel useful. Remove `ReminderThumbProbe` from `IdleView.swift` once a rating is read here.

## Feature status

| Feature | Status |
|---|---|
| Dynamic focus curve | Load-bearing |
| Break activity library | Load-bearing |
| Full-screen overlay + screen lock | Load-bearing |
| Hold-to-skip friction | Load-bearing |
| Skip nudge messages | Presumed load-bearing; no data |
| Reminder messages | Thumbs probe active; awaiting first rating |
| Daily stats footer | Load-bearing |
| One-shot feedback survey | Active; awaiting first response |

## Next

- Read `reminderMsgThumb` from UserDefaults once available; remove probe if rated.
- Rotate Q2 once break-effectiveness responses are in.
- Validate feature utility against `sessions.json` when available (skip rate, session frequency).
