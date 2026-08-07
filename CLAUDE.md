# CLAUDE.md

Guidance for agents working in this repo.

## Read first

[`PURPOSE.md`](PURPOSE.md) is the constitution. It is not background colour — it is the list of
things this app has already tried and deleted, and the reasons why. Before adding anything, check
it against principle 5 (smallest surface) and the four questions under "What guides changes". The
default answer to a new feature here is no.

This is a personal tool with one user, not a product. There is no roadmap, no v2, and no
population to generalise for.

## Commands

```bash
swift run                      # launches into the menu bar, no Dock icon
~/.swiftly/bin/swift test      # bare Command Line Tools ship no testing runtime; use a full toolchain
./build-app.sh <version> <build>
```

CI runs the suite on every push and PR (`.github/workflows/ci.yml`).

## Shape of the code

`Core/PomodoroCore.swift` is a pure state machine (idle → focus → break). Everything in `Logic/`
is pure and unit-tested — put decisions there, not in views or services. `Services/` owns the
impure edges (timers, CoreAudio, screen lock, notifications). `Views/` renders and does not decide.

The break card is the product. `Resources/activities.json` and the string pools in
`Logic/Messages.swift` and `Logic/Nudges.swift` are **content, curated in source** — no editor, no
settings pane, no per-user persistence. Editing them is a normal, expected change; adding UI to
edit them is not.

## Writing user-facing strings

Second person, imperative, specific. "Find a doorway, forearm against the frame, step forward"
beats "do a chest stretch". No praise, no scoring, no streaks, no exclamation marks. Claims made
in reminder copy have to survive a literature check — see the research note below for two that
did not.

Remember the screen locks 30 seconds into every break: any instruction longer than one beat will
be read once and then recalled from memory in a corridor. Write for that.

---

# Research note — recovery messaging (2026-08-07)

Investigation into improving the break-card messaging. Findings are durable; the resulting plan is
[`SPEC_RECOVERY_MESSAGING.md`](SPEC_RECOVERY_MESSAGING.md).

**What this note describes is the library as measured on 2026-08-07.** Spec §2 has since landed —
the medium band went 2 → 10, back-to-back repetition went to 0% in every cell, and the `energy`
field is gone. The measurements below are kept as the record of *why*, not as current state. Spec
§3 and §4 are unstarted, so everything said here about the caption and about under-filled
prescriptions still holds.

## Measured: where repetition actually lives

Simulated `ActivitySelector` against the real library (20k draws per cell, replaying the recency
and category soft rules exactly as `Logic/ActivitySelector.swift` applies them):

| Break band | Time of day | Pool size | Same activity twice in a row |
|---|---|---|---|
| medium (>6 min) | morning | **1** (`stairs`) | **100%** |
| medium | midday | 2 | 43% |
| medium | afternoon | 2 | 43% |
| medium | end of day | **0** → falls back to short library | n/a |
| short (≤6 min) | any | 20–24 | 0% |

The library is 24 short / 2 medium. Repetition is not spread thinly across the app — it is total,
and confined to the *longest* breaks, which the curve hands you at peak hours. README's Open Q #2
("Enough variety that recency + category rotation keep back-to-back breaks distinct") is true for
the short band and false for the medium band.

Two mechanics compound it: the recency window is only `prefix(3)`, and every `soft` filter in
`ActivitySelector` is a no-op when it would empty the pool — so with a two-item pool both the
recency rule and the category rule silently disable themselves. Both existing medium activities
are category `walk`, so the category rule can never fire there even in principle.

## Measured: library composition

26 activities — `inspiration` 8, `stretch` 6, `walk` 4, `eye_rest` 3, `breathwork` 2, `hydration`
2, `mindfulness` 1.

`inspiration` (cycling anecdotes and quotes) is 8 of the 24 short activities and lands on **28% of
short breaks** in steady state. Those are the only activities that leave you in the chair, reading
— and 30 seconds later the screen locks, so you are sitting in front of a dark display recalling a
Pantani stage. They score on psychological detachment but fail PURPOSE principle 3's own test
("out of the chair and out of the screen").

Daylight / distance-viewing — the best-evidenced and least socially awkward recovery available to
an office worker — is 4 of 26.

## Found: dead schema — resolved

`activities.json` authored an `energy` field on every entry (24 `gentle`, 1 `moderate`,
1 `active`). `Activity` never declared it, so `JSONDecoder` discarded it silently. Deleted
2026-08-07: at 24 of 26 `gentle` the data carried no signal, and a field nothing reads is a lie in
the file. Re-add it deliberately if curve-matched effort ever earns its way in.

## Found: the most-repeated string in the app is not an activity

`ReminderMessages.lineFor(date:)` picks one line per calendar day and the card shows it on **every
break that day** — 6–8 identical impressions, by design (§4.5). It is also selected independently
of the activity beneath it, so "Directed attention is a limited resource" routinely sits above a
chest opener. Activity repetition was the reported complaint; caption repetition is the larger one.

Two lines in the pool do not survive a literature check and should go:

- *"Micro-breaks reduce the build-up of mental fatigue hormones."* — there is no such class of
  hormone.
- *"Movement between sessions clears metabolic byproducts from the brain."* — glymphatic clearance
  is a sleep phenomenon, not a five-minute-walk one.

## Evidence base

Consensus among the recovery-psychology and human-factors literature, as it bears on this app:

- **Break length is the moderator that matters for performance.** Micro-breaks reliably lift vigor
  (d = .36) and cut fatigue (d = .35), but performance recovery scales with break length and
  recovering from highly depleting work needs more than 10 minutes —
  [Albulescu et al. 2022, PLOS ONE](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0272460).
  Corollary for this repo: the medium band is where the recovery actually happens, and it is the
  band with the two-item library.
- **A phone break is not a break.** Phone breaks produced the same cognitive depletion as *no
  break at all* — 19% slower and 22% fewer problems solved afterward, versus other break media —
  [Kang & Kurtzberg 2019](https://pubmed.ncbi.nlm.nih.gov/31418586/). Any unprescribed minute
  inside a break is a minute the phone fills, which makes under-filled prescriptions actively
  costly, not merely wasteful.
- **Nature and distance viewing are absurdly cheap.** 40 seconds of a green roof view sustained
  attention and reduced errors versus a concrete control —
  [Lee et al. 2015](https://www.sciencedirect.com/science/article/abs/pii/S0272494415000328).
- **Detachment, relaxation, autonomy and mastery are the recovery experiences with the most
  consistent within-person effects** (DRAMMA); meaning and affiliation are considerably weaker —
  [Steed et al. 2021](https://journals.sagepub.com/doi/abs/10.1177/0149206319864153).
- **Preferred activities and earlier breaks recover more resources**, and there was no evidence
  that non-work activities beat work-related ones —
  [Hunter & Wu 2016, JAP](https://pubmed.ncbi.nlm.nih.gov/26375961/). This is the one finding that
  cuts *against* PURPOSE principle 3's zero-autonomy prescription; see the spec's open questions.
  The curve already front-loads breaks in the morning by accident of design, which is aligned.
- **Interrupting at a task breakpoint reduces annoyance and frustration** (though Adamczyk &
  Bailey found no effect on resumption cost specifically) —
  [review, Front. Psychol. 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11775001/). The app
  interrupts on a fixed timer and cannot see task structure without monitoring that principles 5
  and 6 forbid.
- **A "ready-to-resume" plan formed before an interruption cuts attention residue** and sharply
  improves performance on the interrupting task —
  [Leroy & Glomb 2018, Organization Science](https://ideas.repec.org/a/inm/ororsc/v29y2018i3p380-397.html).
  Mechanism is the *forming*, not the writing down — so an instruction-only version costs no
  surface. Deferred, not rejected.
- **Chore and errand breaks deplete rather than restore.** Do not add "tidy your desk" style
  activities to the library, however virtuous they look.
- **Self-consciousness in shared offices is a documented barrier** to workplace stretching. Several
  current activities (`calf_raises`, `shoulder_openers`, `five_senses`) assume privacy the user may
  not have at a hot desk.

## Ideas considered and not taken forward

Ranked below the three in the spec, kept here so they are not re-derived from scratch:

4. Cap the `inspiration` share; retire story/quote items after one read (an anecdote has no reread
   value, a stretch does).
5. Ready-to-resume line during the overlay fade-in — uses time that is already dead.
6. One swap per break ("not this one" → exactly one alternative, never a menu). Strongest of the
   dropped four on evidence; loses to PURPOSE principle 3.
7. Office-safety pass over the library, plus fixing arbitrary time-of-day tags (`window_stand`
   excludes midday; `short_walk` excludes morning, for no stated reason).

Also considered: widening the recency window past 3; category-deficit weighting across the day;
per-activity phrasing variants; dropping the "Loosen the neck?" question-opener that appears on
~17 of 26 instructions; showing the "why" only on first exposure; auto-retiring an activity refused
three times; a resumption cue at break end instead of a bare chime; a richer skip-nudge pool
(currently 5 lines).
