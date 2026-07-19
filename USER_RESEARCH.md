# User Research

_Single user. Personal tool. Mac only._

## Usage data

Real data lives on the user's machine at `~/Library/Application Support/DynamicPomodoro/sessions.json` (not readable from remote review containers).
Reviewed 2026-07-19 (consultant review, on-machine): Apr 22 – May 24 usage shows 89% focus completion (target >80%) and 94% break completion (target >60%).
The loop works when used.
54% of real session starts fell outside the configured 09:00–18:00 workday (large 06:00–07:00 and 21:00–22:00 blocks), so 65% of sessions ran at the minimum duration and the curve rarely engaged.
Calibrating the workday settings to the real day is a user action, not a code change.
Usage paused after 2026-05-24 for an external reason (work-laptop install policy), not product dissatisfaction.

## Retired probes

- **Reminder-quotes thumbs probe** – resolved 👍 (read 2026-07-19 from the installed app's defaults, `reminderMsgThumb = up`).
  The quotes stay; the probe was removed from `IdleView`.
- **One-shot feedback survey** – fired its once-per-account prompt on 2026-05-14: satisfaction 5/5, Q2 (rev 1) "Which part of your workday feels hardest to focus through?" → "End of day".
  The once-per-account gate made every later Q2 rotation a dead channel, so the whole apparatus (~400 LOC) was deleted on 2026-07-19 per PURPOSE principle 5.
  `feedback.json` remains on disk as historical data.

## Feature status

| Feature | Status |
|---|---|
| Dynamic focus curve | Load-bearing |
| Break activity library | Load-bearing |
| Full-screen overlay + screen lock | Load-bearing (overlay collapse on macOS 26 fixed 2026-07-19) |
| Hold-to-skip friction | Load-bearing |
| Skip nudge messages | Presumed load-bearing |
| Reminder messages | Rated 👍 – keep |
| Daily stats footer | Load-bearing |

## Next

- Validate skip rate and session frequency via `sessions.json` once usage resumes (work-laptop install decision pending).
- "End of day" is the hardest-to-focus period (survey, 2026-05-14) and evening sessions clamp to minimum by design – revisit only if the data says otherwise.
