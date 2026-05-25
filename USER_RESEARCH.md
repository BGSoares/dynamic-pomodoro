# User Research

_Single user. Personal tool. Mac only._

## Usage data

No session or feedback data available (remote container, no `~/Library/Application Support/DynamicPomodoro/`). Logging is well-instrumented — sessions.json and feedback.json will be available once the app runs on the user's machine. Feedback gate requires 5 completed focus sessions — not yet triggered.

## Active feedback question (Q2, rev 2)

"Do the breaks actually help you refocus?" — multiple choice: Yes, consistently / Usually / Sometimes / Rarely. Measures core value proposition. No responses yet.

## Active thumbs probe

**Reminder quotes** — 👍/👎 widget on `IdleView` after the first completed break (once, gated by `reminderMsgThumb` in UserDefaults). Question: do the short italic lines shown on the break screen feel useful? Remove `ReminderThumbProbe` from `IdleView.swift` once a rating is read here.

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
- Read `feedback.json` once available; rotate Q2 if break-effectiveness responses are in.
- Read `sessions.json` to validate feature utility against actual usage patterns.
- Quick-skip detection (breakSkipped with elapsed < 15s) is inferrable from existing log without new instrumentation.
