# Purpose

A personal tool to make a day of deep work feel like a day of good training — sessions calibrated to capacity, recovery taken seriously, and discipline built into the structure rather than relying on willpower.

This is not a product. It is one person's working environment, written down in code.

---

## The problem this exists to solve

A fixed 25-minute pomodoro doesn't fit the shape of a real workday. Cognitive capacity is not flat — it rises through the morning, peaks around the middle of the day, and falls off in the afternoon. Pretending otherwise wastes the good hours and burns the bad ones.

The other half of the problem is breaks. Most timers treat the gap between sessions as "free time." In practice, that becomes another tab, another scroll, another five minutes of the same kind of attention you just spent — which is the opposite of recovery. A break with no instruction collapses back into work-shaped behaviour.

This app fixes both. Focus durations follow a bell curve across the workday. Breaks come with a specific, prescribed activity — physical, sensory, or contemplative — that pulls you out of the chair and out of the screen.

---

## Core principles

**1. Match intensity to capacity, not to the clock.**
A focus session is what fits *this hour of this day*, not a constant. The cosine curve in [DurationCurve.swift](Sources/DynamicPomodoro/Logic/DurationCurve.swift) is the literal expression of this principle. The first session of the day is always the shortest — readiness is a function of time-since-start, not just clock time.

**2. Rest is part of the work, not a tax on it.**
This is the cycling metaphor that runs through the entire app: pros recover between intervals, and that recovery is *why* the intervals get better. The reminder messages in [Messages.swift](Sources/DynamicPomodoro/Logic/Messages.swift) are not motivational filler — they are the scientific and athletic argument for why a break is non-negotiable.

**3. Recovery is active, specific, and prescribed.**
A break that says "take 5 minutes" produces another browser tab. A break that says "find a doorway, forearm against the frame, step forward, feel the chest open" produces a body that is no longer collapsed over a keyboard. The activity library is the content of the app. It is curated, not crowd-sourced, not customisable through the UI — it is the opinion of the tool.

**4. Friction belongs in the right places.**
Starting a focus session is one click. Skipping a break costs a 15-second hold and one final line of resistance. The screen locks 30 seconds into the break. Every other display is blacked out. This is not a productivity-shaming UX — it is the recognition that the impulse to skip a break is *exactly* the moment willpower fails, so the tool absorbs that decision instead of asking you to make it.

**5. The smallest surface that does the job.**
Four settings. No onboarding. No accounts. No cloud. No streaks, scores, leaderboards, or weekly summary emails. The recent collapse from ~4k to ~1.8k LOC was not refactoring for its own sake — it was deleting everything that wasn't the core loop, and the core loop is small. New features have to earn their way in past this principle.

**6. Local, private, native.**
Settings live in `UserDefaults`. Sessions log to `~/Library/Application Support/DynamicPomodoro/sessions.json`. Nothing leaves the machine. Native Swift was chosen over Electron specifically for battery, polish, and menu-bar fit — not portability. There is no mobile app and there will not be one.

---

## How this is supposed to make my life better

- **Better-shaped days.** The 09:00 session is short on purpose, so I warm into work instead of sprinting from cold. The midday sessions are long because that's when I can actually use the time. The late-afternoon sessions taper because pretending I have peak focus at 17:30 is what produces 18:30 bad code.

- **Recovery I actually take.** The full-screen overlay, the screen lock, the hold-to-skip — together they take the decision out of my hands at the moment the decision is most likely to be the wrong one. I don't have to "be disciplined enough" to take a break; I have to be disciplined enough to override the tool, which is a higher bar than I will usually clear, which is the point.

- **A body that survives a desk job.** Stretches, eye-rests, walks, breathwork — distributed across the day, prescribed at the right times. The cumulative effect over weeks and months is the actual product, not the per-session experience.

- **No decision fatigue about rest.** I don't choose what to do in the break. The tool does. I just do it.

---

## What this is not

- **Not a productivity app.** It does not try to make me do more sessions. The success metric for "more pomodoros" is explicitly absent. If it does its job, I do *better-quality* sessions, not more of them.

- **Not a wellness app.** It will not track my mood, my heart rate, my sleep, or my breath. It assumes I know what those things are and trusts me to know whether I am tired.

- **Not a coaching app.** It does not score me, rank me, or congratulate me. A skipped break is logged, not flagged. There are no achievements.

- **Not configurable infinitely.** The four settings are: workday start, workday end, min focus minutes, max focus minutes. That is the entire surface of personalisation. Everything else is the opinion of the tool. If I disagree with the opinion, I edit the source — that is the privilege of a personal tool over a product.

- **Not building toward a v2 product.** There is no roadmap. There is the loop, and there are bug fixes and small refinements when the loop reveals them. The roadmap is "use it for another week."

- **Not cross-platform, not mobile, not cloud.** All three would compromise principles 5 and 6 to serve a population of zero people other than me, who already have a Mac at every desk I sit at.

---

## What guides changes

When deciding whether to add, remove, or change something, the order of priority is roughly:

1. **Does it serve the core loop?** Focus → break → focus. If not, why is it here?
2. **Does it reduce friction at the wrong moment?** Anything that makes it easier to skip a break is a regression in disguise.
3. **Does it grow the surface area?** A new setting, a new toggle, a new screen — each one has to clear a high bar. The recent collapse is the reference point.
4. **Does it stay local and native?** A feature that needs a server, an account, or a third-party SaaS does not belong here.

---

## A note for future me (or any agent reading this)

The hardest decisions in this app are the ones about what *not* to do. The codebase has at various points held: an onboarding flow, a curve preview, a cycling-news RSS reader, a calendar sync, a custom-activity editor, media auto-pause, and more. Each of those was added in good faith and then deleted because it didn't earn its place in the loop. That oscillation is not failure — it is the design process. New ideas are cheap; the work is in noticing when they have stopped paying rent.

When in doubt, the answer is usually: simpler, more local, more opinionated, more cycling.
