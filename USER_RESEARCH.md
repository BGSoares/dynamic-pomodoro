# User Research

_Single user. Personal tool. Mac only._

## Usage data

No session or feedback data available (dev machine, no `~/Library/Application Support/DynamicPomodoro/`). The feedback survey gate is 5 completed focus sessions — not yet reached.

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

- Read `reminderMsgThumb` from UserDefaults once available; remove probe widget if rated.
- Read `feedback.json` and `sessions.json` once available to validate feature utility.
