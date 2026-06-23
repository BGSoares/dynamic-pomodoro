# User Research

_Single user. Personal tool. Mac only._

## Usage data

No session or feedback data readable in this environment (remote container, no `~/Library/Application Support/DynamicPomodoro/`). Data accumulates on the user's machine. _(Reviewed 2026-06-23: still none. Feedback gate needs 5 completed focus sessions; thumbs probe needs 1 completed break — neither triggered yet.)_

## Active feedback question (Q2, rev 2)

"Do the breaks actually help you refocus?" — multiple choice: Yes, consistently / Usually / Sometimes / Rarely. No responses yet.

## Active thumbs probe

**Reminder quotes** — 👍/👎 widget on `IdleView` after first completed break (once, gated by `reminderMsgThumb`). Remove `ReminderThumbProbe` from `IdleView.swift` once a rating is read here.

## Feature status

| Feature | Status |
|---|---|
| Dynamic focus curve | Load-bearing |
| Break activity library | Load-bearing |
| Full-screen overlay + screen lock | Load-bearing |
| Hold-to-skip friction | Load-bearing |
| Skip nudge messages | Presumed load-bearing |
| Reminder messages | Thumbs probe active |
| Daily stats footer | Load-bearing |
| One-shot feedback survey | Active |

## Next

- Read `reminderMsgThumb` and Q2 responses once available; act on whichever lands first.
- Validate skip rate and session frequency via `sessions.json`.
