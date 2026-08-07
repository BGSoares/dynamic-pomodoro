# Feature spec — Recovery messaging

**Status:** §2 (Change 1) **implemented**. §3 and §4 proposed, not started.
Research complete — [`CLAUDE.md`](CLAUDE.md), research note 2026-08-07.
**Scope:** Three changes to the break card — one pure content change, one optional schema field plus
one line of rendering, one rewrite of `Logic/Messages.swift`. No new windows, no new settings, no
new services, no new persistence.

The break card has three layers: *which* activity you get, *what the activity asks of you*, and
*the line above it*. Each change below fixes exactly one layer.

---

## §1 Why

The reported complaint was repetition of break activities. Measurement (§1.1) says repetition is
real but is not where it was assumed to be, and that two larger problems sit next to it.

### §1.1 Repetition is total, and confined to the long break

Simulating `ActivitySelector` against the shipped library, 20k draws per cell, replaying the
recency and category soft rules exactly:

| Band | Time of day | Pool | Same activity twice in a row |
|---|---|---|---|
| medium (>6 min) | morning | **1** — `stairs` | **100%** |
| medium | midday | 2 | 43% |
| medium | afternoon | 2 | 43% |
| medium | end of day | **0** → relaxes to the short library | n/a |
| short (≤6 min) | any | 20–24 | 0% |

The library is 24 short / 2 medium. Every long morning break this app has ever served said
*Stairs*; every long afternoon break is a coin flip between two items and lands on the same one
43% of the time; long end-of-day breaks silently get a short-break activity.

Two mechanics compound it. The recency window is `prefix(3)`, and every `soft` filter in
`ActivitySelector` is a deliberate no-op when it would empty the pool — so at pool size 2 both the
recency rule and the category rule disable themselves. Both medium activities are category `walk`,
so the category rule could never fire there regardless.

This is also the band that matters most: break *length* is the moderator that predicts performance
recovery ([Albulescu et al. 2022](https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0272460)),
so the app's most valuable recovery windows run on a two-item loop.

### §1.2 The prescription ends before the break does

"3 sets of 15 calf raises" is ninety seconds inside a five-minute break. Only 8 of the 26
activities say how to fill their duration ("for the full break", "until the break feels spent").
Of the other 18, nine are explicitly bounded by a rep count or a hold time and finish early, and
nine are open-ended with no stated end at all — you don't know when you're done, which lands in the
same place.

That leaves two to seven unprescribed minutes on a locked screen, which is where the phone goes —
and a phone break produces the same cognitive depletion as no break at all
([Kang & Kurtzberg 2019](https://pubmed.ncbi.nlm.nih.gov/31418586/)). An under-filled prescription
is not merely incomplete; it converts a break into a non-break.

### §1.3 The most-repeated string in the app is the caption

`ReminderMessages.lineFor(date:)` picks one line per calendar day and shows it on *every* break
that day — 6–8 identical impressions. It is also chosen independently of the activity beneath it,
so the argument and the instruction routinely disagree ("Directed attention is a limited resource"
above a chest opener). By the fourth impression it is wallpaper, and it never once explains the
thing actually on screen.

---

## §2 Change 1 — A real library for the long break

**Implemented.** Pure content, plus the invariant test that would have caught the defect (§6.1).

**Acceptance criterion:** every `(band, time_of_day)` cell holds **≥ 6 activities across ≥ 3
categories**. Six is the floor at which `prefix(3)` recency leaves a real choice and the category
rule can still fire; three categories is what stops the category rule from being structurally dead.

Eight medium-band activities added to `Resources/activities.json`, taking the band from 2 to 10:

| id | category | suitable_times |
|---|---|---|
| `outdoor_block` | walk | all four |
| `daylight_stand` | walk | morning, midday, afternoon |
| `corridor_loop` | walk | all four |
| `mobility_flow` | stretch | all four |
| `extended_exhale` | breathwork | afternoon, end_of_day |
| `body_scan` | mindfulness | afternoon, end_of_day |
| `palming` | eye_rest | all four |
| `kettle_and_window` | hydration | all four |

`daylight_stand` skips end-of-day (it may be dark); `extended_exhale` and `body_scan` are
down-regulating and only earn their place once there is something to down-regulate from. Every
other tag is "all four", because no real reason to exclude one was available — which is the
standard the two fixed tags below are held to as well.

Resulting medium cells: **morning 8, midday 8, afternoon 10, end of day 8**, spanning 4–6
categories each. Simulated back-to-back repetition drops from 100% / 43% / 43% / n-a to **0% in
every cell**, and no single activity exceeds a 19% share.

A ninth candidate, a medium hip-flexor stretch, was **dropped**: `hip_flexor_stretch` sits in the
`removedIDs` regression guard in `ActivitySelectorTests`, so an earlier pass deliberately removed
it. The squashed bootstrap commit means the reasoning is lost, but re-adding the same activity
under a different id would route around a decision this repo made on purpose. If the reason turns
out to be forgettable, add it back deliberately and delete the guard entry.

Two curation notes carried from the research:

- `corridor_loop` and `palming` exist so bad weather and a shared office never force a fallback.
  Several current activities assume privacy the user may not have at a hot desk.
- **No chore or errand activities.** "Clear your desk", "empty the dishwasher" and similar look
  virtuous and deplete rather than restore. This is a standing exclusion, not a scope decision.

`daylight_stand`, `outdoor_block` and `kettle_and_window` deliberately weight the band toward
daylight and distance viewing, which is 4 of 26 activities today and is the best-evidenced, least
socially awkward recovery available to an office worker
([Lee et al. 2015](https://www.sciencedirect.com/science/article/abs/pii/S0272494415000328)).

**Also in this change:** two time-of-day tags with no stated rationale, shrinking pools for free,
are now "all four" — `window_stand` excluded `midday` (when the light is best) and `short_walk`
excluded `morning` and `end_of_day`. `stairs` keeps its end-of-day exclusion: declining to send
someone up a stairwell at 17:30 is a defensible opinion, unlike the other two.

**Also in this change:** the dead `energy` field is deleted from all 26 existing entries and absent
from the 8 new ones (§9.1).

---

## §3 Change 2 — Prescribe the whole break

### §3.1 Schema

Add one optional field to `Activity` and to every JSON entry that needs it:

```swift
/// Beat two: what to do once the first beat is done, for the rest of the break.
/// Optional — an activity already written to fill its duration (`twenty_twenty_twenty`)
/// has no second beat and renders exactly as it does today.
let settle: String?
```

Optional, so decoding stays backwards-compatible and the field can be filled in over several
passes rather than in one sitting.

### §3.2 Copy rule

Beat one is the movement and stays as written. Beat two is what carries you to the chime, and
should default to distance viewing, daylight, or breath — the three things that need no equipment,
no privacy, and no clock-watching. It must be recallable *after* the screen locks 30 seconds in, so
it is one clause, no counting, no sequence.

```
name:        Calf raises
instruction: Stand at your desk. Slow rise onto the balls of your feet, slow lower. 3 sets of 15.
settle:      Then stand at the window and let your eyes go long until the chime.
```

### §3.3 Rendering

`BreakOverlayView`, in the existing activity `VStack`, below `instruction`:

```swift
if let settle = activity.settle {
    Text(settle)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 140)
        .frame(maxWidth: 900)
}
```

Quieter and narrower than `instruction`, so the card reads as one prescription with a second beat
rather than two competing instructions. `BreakMirrorView` is unchanged — it is a placeholder, not a
prescription.

---

## §4 Change 3 — The caption argues for the activity

### §4.1 Model

`ReminderMessages.pool` becomes a pool of tagged messages:

```swift
struct ReminderMessage {
    let text: String
    /// Categories this line argues for. Empty = general — eligible for any activity,
    /// used only when no category-specific line is available.
    let categories: Set<Activity.Category>
}
```

The existing "Science of rest" lines tag to the category they actually describe (the 60cm-eyes line
→ `eyeRest`; the posture line → `stretch`; the nasal-breathing line → `breathwork`). "Cost of
skipping", "Training metaphors" and "Commitment" stay general — they argue for taking a break at
all, which is true regardless of what the break contains.

**Delete two lines outright.** "Micro-breaks reduce the build-up of mental fatigue hormones" (no
such class of hormone) and "Movement between sessions clears metabolic byproducts from the brain"
(glymphatic clearance is a sleep phenomenon). PURPOSE principle 2 calls these lines "the scientific
and athletic argument"; lines that fail a literature check are not that.

Backfill so that every `Activity.Category` has **≥ 3** specific lines. `inspiration` and `hydration`
have none today.

### §4.2 Selection

```swift
static func line(
    for activity: Activity?,
    date: Date,
    breakOrdinalToday: Int,
    calendar: Calendar = .current
) -> String?
```

1. Eligible pool = messages tagged with `activity.category`. If empty (or `activity` is nil), use
   the general messages.
2. Index deterministically by `(dayOrdinal + breakOrdinalToday) % pool.count`.

Deterministic, so it stays unit-testable without an RNG — matching how `lineFor(date:)` and
`Nudges.assign` already work. Varying by break ordinal is what ends the 6–8 identical impressions;
varying by day ordinal is what stops the same activity always carrying the same line.

`breakOrdinalToday` needs no new storage: it is `SessionLogStore.shownBreakStartsToday().count`,
the same query `Nudges.forBreak` already consumes.

### §4.3 Precedence

Unchanged. A due nudge still takes the slot outright (PURPOSE principle 8), and the card keeps
exactly the shape it has today. `BreakCaption` is untouched; only the `.reminder` payload's
provenance changes.

---

## §5 File map

| File | Change | Status |
|---|---|---|
| `Resources/activities.json` | +8 medium activities; two time-of-day fixes; `energy` deleted | **done** (§2) |
| `Tests/…/ActivitySelectorTests.swift` | §6.1 pool-floor invariant, §6.2 no-repeat walk | **done** |
| `README.md` | Open Q #2 was falsified by the measurement | **done** |
| `Resources/activities.json` | `settle` on entries that need one | §3 |
| `Models/Activity.swift` | `settle: String?` + `CodingKeys` | §3 |
| `Views/BreakOverlayView.swift` | render `settle` | §3 |
| `Logic/Messages.swift` | `ReminderMessage` struct, category tags, `line(for:date:breakOrdinalToday:)`, two deletions, backfill | §4 |
| `Core/PomodoroCore.swift` | pass activity + break ordinal when building `BreakCaption.reminder` | §4 |
| `Tests/…/MessagesTests.swift` | rewrite for the new selector | §4 |
| `README.md` | the §4.5 message-frequency note goes stale when §4 lands | §4 |

`ActivitySelector` itself is **not** changed. Its soft rules are correct; they were starved of a
pool. Widening the recency window past 3 is deliberately deferred until §2's library has run for a
few weeks — fixing the input and the algorithm at once would make the result unattributable.

---

## §6 Testing

swift-testing, in `Tests/DynamicPomodoroTests/`.

### §6.1 Library invariant (the regression guard for §2) — **implemented**

`bundledLibraryMeetsPoolFloorInEveryCell`: for every `(band, time_of_day)` pair, pool size ≥ 6 and
distinct categories ≥ 3. This is the test that would have caught the original defect; it failed on
the shipped library at 1 and 0. A zero in medium/end-of-day was previously invisible because the
band relaxation in `select` hides it.

### §6.2 Selector, with the real library — **implemented**

`bundledLibraryNeverRepeatsBackToBack`: 200 sequential selections per time-of-day and band, feeding
recency and last-category forward, asserting no back-to-back repeat. Not flaky despite the
unseedable `SystemRandomNumberGenerator` — above the §6.1 floor a repeat is structurally impossible,
which is exactly the property being locked in. Share-of-draws is left to the offline simulation
rather than asserted, since that *would* need a seed.

### §6.3 Messages

- A line tagged `eyeRest` is selected for an eye-rest activity; a general line is not preferred over it.
- Categories with no specific line fall back to general, never to nil.
- Same day, different `breakOrdinalToday` → different line (for pools > 1).
- Same activity, different day → different line.
- Neither deleted line survives anywhere in the pool.
- Every category has ≥ 3 specific lines (invariant, guards the backfill).

### §6.4 Activity decoding

An entry without `settle` decodes with `settle == nil`; one with it round-trips.

### §6.5 Manual

Run a real long morning break and a real long end-of-day break — the two cells that are broken
today. Confirm the `settle` line is legible at arm's length and still recallable after the 30s
screen lock, which is the whole reason for the one-clause rule in §3.2.

---

## §7 Further research required

### §7.1 On-machine data — blocked, needs the user

`sessions.json` is not readable from a review container, and usage has been paused since 2026-05-24
pending a work-laptop install decision. None of the following can be answered until it resumes:

1. **Per-activity skip rate.** `SessionLogEntry` already carries `activityID` on break entries and
   a `breakSkipped` kind, so "which activities get skipped" is answerable *today* with a notebook
   and no code change. This is the highest-value unanswered question in the repo: it would tell us
   whether `inspiration` items are loved or endured, which §8 currently guesses at.
2. **Break completion by band.** Is the 94% headline uniform, or do the long breaks — the two-item
   ones — underperform? If they do, §2 has a measurable before/after.
3. **Actual band distribution.** 65% of sessions ran at minimum duration because the workday
   settings were miscalibrated, meaning the medium band may barely have fired in practice. If the
   user recalibrates, §2 goes from latent to urgent. Worth checking before sizing the effort.
4. **Re-entry latency** (break `endedAt` → next focus `startedAt`), already derivable, as the
   control variable — it should not regress when breaks get longer-feeling.

### §7.2 Open questions the literature does not settle

- **Prescribed vs. chosen.** [Hunter & Wu 2016](https://pubmed.ncbi.nlm.nih.gov/26375961/) found
  preferred activities recover more resources, and autonomy is a recovery experience in its own
  right in [DRAMMA / Steed et al. 2021](https://journals.sagepub.com/doi/abs/10.1177/0149206319864153).
  Both cut directly against PURPOSE principle 3's zero-autonomy stance. Neither studied a
  *prescriptive tool* — the comparison is chosen-vs-assigned activity, not
  chosen-vs-assigned-with-one-swap. No study found that resolves this. It is the strongest
  candidate for a future change (one swap, never a menu) and should stay parked until §7.1's skip
  data says whether prescription is actually costing anything.
- **20-20-20 specifically.** It is folk-canonical and sits in the library as `twenty_twenty_twenty`,
  but the trial evidence for the *specific* 20/20/20 parameters is weaker than its ubiquity implies
  — adherence collapses without prompting, and it is usually tested against no intervention rather
  than against simple distance viewing. Worth a targeted read before it keeps headline status;
  distance viewing generally is well supported, the numbers are not.
- **Within-day habituation to a repeated prompt.** §4 assumes reading the same caption 6–8 times a
  day degrades it. That is the consensus direction across warning-fatigue and advertising-wearout
  work, but no study measures it at this exact cadence. §4 is cheap enough not to need the proof;
  do not build anything larger on the assumption.
- **The 30-second screen lock and instruction recall.** The app's own mechanic means every
  instruction is executed from memory. No literature bears on this usefully; it is answerable only
  by the user noticing whether they get beat two right.

### §7.3 Deliberately not researched further

**Task-boundary interruption timing.** Interrupting at a breakpoint reduces annoyance
([review, 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11775001/)), and the app interrupts on a
fixed timer. Acting on this needs task-structure awareness — activity monitoring, editor
integration, or heuristics over window focus — all of which fail principles 5 and 6. The finding is
recorded so it is not rediscovered as a good idea; it is not actionable here.

**Ready-to-resume plan** ([Leroy & Glomb 2018](https://ideas.repec.org/a/inm/ororsc/v29y2018i3p380-397.html)).
Deferred, not rejected — see §8.

---

## §8 Non-goals & accepted trade-offs

**Non-goals (this iteration):**

- **No swap, no skip-this-activity, no preference memory.** §7.2 explains why this is parked rather
  than dismissed. Anything that lets the user out of the prescribed activity also makes it cheaper
  to be out of the break, which is guide question #2.
- **No ready-to-resume line in the fade-in.** It is a genuinely good idea with good evidence and it
  costs no surface, but it is a fourth change to the same card in one pass. Ship these three,
  live with them, then decide.
- **No `ActivitySelector` algorithm change.** §5 explains the attribution reasoning.
- **No per-activity phrasing variants, no first-exposure-only "why", no auto-retiring of read-once
  story items.** All three need per-activity state the app deliberately does not keep.
- **No new setting.** The four settings are the whole surface (principle 5).

**Accepted trade-offs:**

- The library grows from 26 to 34 activities. Principle 5 is about *surface*, not content — the
  activity library is explicitly named as "the content of the app" in principle 3 — but it is still
  more to curate and keep good.
- `settle` will be nil on most short activities at first, so §1.2's dead-time problem is only
  partly solved on day one. Filling them in is a content pass, not a follow-up feature.
- Making the caption category-specific means a given line appears less often overall, so the
  strongest lines get less airtime. Judged a good trade against 6–8 identical impressions.
- The caption was rated 👍 in `USER_RESEARCH.md` and §4 changes it. The probe apparatus that
  produced that rating was deleted (principle 5) and will not be rebuilt to re-check.

---

## §9 Open questions for the implementing PR

1. ~~**The dead `energy` field.**~~ **Decided 2026-08-07: deleted.** `gentle` on 24 of 26 entries
   carried no signal, and a field nothing reads is a lie in the data file. Re-add it deliberately
   if curve-matched effort ever earns its way in.
2. **Should `settle` be required rather than optional?** Recommendation: optional. Two activities
   genuinely fill their own duration, and forcing a second beat on them would produce filler — the
   exact thing §3 exists to remove.
3. ~~**Should §2 land as its own PR, ahead of §3 and §4?**~~ **Decided 2026-08-07: yes**, and it
   has. §3 and §4 are unstarted; let §2 run for a few weeks first so its effect is attributable.
4. **Retire `history_*` / `wisdom_*` items after one read?** An anecdote has no reread value the way
   a stretch does. Recommendation: not now — it needs per-activity persistence, and §7.1's skip
   data should decide whether `inspiration` shrinks instead.

---

## §10 PURPOSE alignment

- **Serves the core loop (guide #1):** all three changes are the break half of focus → break →
  focus, and §3 targets the specific failure mode where a break stops being a break.
- **Recovery is active, specific, prescribed (principle 3):** §3 is that principle applied to the
  *whole* break rather than its first ninety seconds. §2's daylight weighting pushes the library
  further toward "out of the chair and out of the screen"; the `inspiration` block, at 28% of short
  breaks, is currently the largest exception to it.
- **Friction in the right places (principle 4):** unchanged. Nothing here makes a break easier to
  skip; the swap idea, which would, is parked in §8 for exactly that reason.
- **Smallest surface (principle 5):** zero new windows, zero new settings, zero new services, zero
  new persistence. One optional JSON field and one `Text` view. The largest diff is content.
- **Local, private, native (principle 6):** nothing added touches the network, disk, or any
  permission.
- **A nudge rides a break (principle 8):** §4.3 preserves nudge precedence and the card's shape
  exactly.

---

## §11 Decision log

| Decision | Reasoning |
|---|---|
| Fix the library before the selector | The soft rules are correct and were starved of a pool; changing both at once makes the result unattributable |
| Pool floor of 6 across ≥ 3 categories | The point at which `prefix(3)` recency leaves real choice *and* the category rule can still fire |
| `settle` optional, not required | Two activities already fill their duration; mandatory second beats would be filler |
| Caption keyed to category, not to activity id | Per-activity lines are 26 more strings to keep good, for a gain the category grouping already delivers |
| Deterministic caption index, no RNG | Matches `lineFor(date:)` and `Nudges.assign`; keeps the whole thing unit-testable |
| Deleted two reminder lines | Principle 2 calls this pool the scientific argument; lines that fail a literature check are not that |
| Swap-per-break parked, not rejected | Best-evidenced of the rejected ideas, but it contradicts principle 3 and needs §7.1's skip data first |
| Chore/errand activities permanently excluded | They deplete rather than restore; recorded so the idea is not rediscovered |
| `energy` deleted rather than wired up | 24 of 26 entries were `gentle`; the field carried no signal and nothing read it |
| Medium hip-flexor stretch dropped from §2 | `hip_flexor_stretch` is in the `removedIDs` guard; a new id for the same activity would route around a deliberate removal |
| `stairs` keeps its end-of-day exclusion | Unlike the two tags that were fixed, "no stair intervals at 17:30" is a real opinion, not an oversight |
