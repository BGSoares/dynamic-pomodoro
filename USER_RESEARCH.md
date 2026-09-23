# User Research

_Single user. Personal tool. Mac only._

This file is where the owner records real dogfood findings against their own `sessions.json` —
not a template to fill in once, but a living log that gets appended to and pruned the way
`CLAUDE.md`'s research notes are: measurements first, decisions after, stale entries deleted once
a spec section lands.

## Usage data

Real data lives on the user's machine at `~/Library/Application Support/DynamicPomodoro/sessions.json` (not readable from remote review containers).
Nothing has been recorded here yet. When you have a few weeks of real use, capture: focus and
break completion rates against the targets below, how much real usage falls inside vs. outside
the configured workday window (a curve calibrated to the wrong hours won't engage), and any
qualitative signal on what's hardest to sustain during the day.

## Retired probes

- **Reminder-quotes thumbs probe** – a one-bit 👍/👎 read from the installed app's defaults to
  validate the reminder-message pool. Once it settled positive, the probe itself was removed from
  `IdleView` — it had answered its question.
- **One-shot feedback survey** – a once-per-account prompt that captured a satisfaction rating and
  one open-ended question. The once-per-account gate made every later rotation of the question a
  dead channel, so the whole apparatus (~400 LOC) was deleted per PURPOSE principle 5. This is the
  shape a probe should take here: cheap, temporary, and deleted once it has an answer — see
  `CLAUDE.md`'s research-note convention for the standard.

## Feature status

| Feature | Status |
|---|---|
| Dynamic focus curve | Load-bearing |
| Break activity library | Load-bearing |
| Full-screen overlay + screen lock | Load-bearing |
| Hold-to-skip friction | Load-bearing |
| Skip nudge messages | Presumed load-bearing |
| Reminder messages | Rated 👍 – keep |
| Daily stats footer | Load-bearing |

## Next

- Validate skip rate and session frequency via `sessions.json` once you have real usage to look at.
- Revisit the workday settings (start, end, min/max focus minutes) against your actual day before
  trusting the curve's shape — a misconfigured window is the most common reason the medium/long
  bands never engage.
