---
description: Identify the greatest sources of complexity in the app and propose the smallest cuts that remove them
---

Find code that is not earning its place and propose the smallest cut that removes it. The goal is reduction in lived complexity — fewer lines, fewer states, fewer branches — not a tidier version of the same thing. Refactors that move complexity around without removing it do not count.

## Read first, before opening any source file

1. [`PURPOSE.md`](../../PURPOSE.md) — the constitution. Every proposal is tested against it.
2. [`USER_RESEARCH.md`](../../USER_RESEARCH.md) — what is currently load-bearing vs. on probation.
3. [`README.md`](../../README.md) — architecture map and "Not built" list.

If a proposal would violate `PURPOSE.md` (e.g. "make X configurable", "add adaptive learning", "extract a service layer", "introduce a plugin point"), drop it before reporting. The recent ~4k → ~1.8k LOC collapse is the reference point; you are continuing that trajectory, not reversing it.

## Lenses for complexity

Use all of these. LOC alone is misleading.

- **Lines per unit of delivered behaviour.** A 300-line file that does one thing the user cares about is fine. A 50-line file with three things nobody uses is not.
- **State surface.** Count every mutable property reachable from the running app: `@State`, `@Published`, `@AppStorage`, `UserDefaults` keys, file-backed stores, singletons. State is the most expensive thing to add and the hardest thing to remove. Derived state that is also stored is the highest-yield cut.
- **Branches with no live arm.** `if cond { A } else { B }` where `cond` never (or always) holds in practice. Includes optional unwraps for values guaranteed to exist, fallbacks for inputs that cannot occur, and selector relaxations that never fire on the real activity library.
- **Abstractions with one implementation.** A protocol, a service, an enum case, a `Codable` DTO that exists but is never varied. The cost of the layer is paid every read; the substitutability benefit is never collected.
- **Ceremony per real line.** Initializers that exist only to satisfy a framework, getters that return a stored property unchanged, model↔DTO mappings that copy field-for-field, manual `Codable` conformances that the synthesised one would handle.
- **Multiple ways to do one thing.** Two clocks, two persistence paths, two notification channels, two computations of the same number, two places that decide whether a break has started.
- **Dead and dormant.** Resources not referenced, fields written but never read (or read but never written), flags never flipped, `// TODO` paths, version-gated branches whose other version has been removed, scaffolding for a feature that was deleted.
- **Coupling latency.** Code where a one-line change in user-visible behaviour requires edits in N files. The N is the measure.

## Essential complexity register — do NOT propose simplifying

These exist by intent. Flagging them is noise.

- The cosine curve and the first-session-of-day rule in `Logic/DurationCurve.swift`. The unevenness IS the app (PURPOSE §1).
- The full-screen overlay + hold-to-skip + screen-lock combination. The friction is the feature (PURPOSE §4).
- The curated activity library and its category / band / time-of-day filtering in `Logic/ActivitySelector.swift` and `Resources/activities.json`. The opinion is the product (PURPOSE §3).
- The cycling-themed reminder messages and narrative activities. Not decoration (PURPOSE §7).
- The four settings (workday start, workday end, min focus, max focus). The smallness is the design (PURPOSE §5).

If you think one of these is genuinely overweight, the bar is naming the specific implementation cost (not the feature) and proposing a cut that preserves the behaviour exactly.

## Steps

1. **Sweep, don't dive.** Build a map: every file under `Sources/DynamicPomodoro/`, its LOC, and one line on what it actually does for the running app. Note the top files by LOC, by `@State`/`@Published` count, and by number of `UserDefaults` keys touched. Spend ≤10 minutes here.

2. **Apply the lenses.** For each candidate hotspot, identify which specific lens it fails, with a concrete signal. "BreakOverlayView.swift:120–180 — six `@State` properties, four derived from a single source of truth in `PomodoroCore`" beats "this file is messy." If you cannot point at the signal, the hotspot is not real.

3. **Name the load.** For each candidate, write the one sentence that says what would break — in user-visible behaviour — if the code were deleted. If you cannot name it, that is the strongest signal the code is dead. If the load is real but the implementation is heavier than the load demands, that is the second-strongest signal. Tests passing after a hypothetical deletion is supporting evidence, not proof.

4. **Propose the smallest cut.** Not "refactor X." A concrete instruction: "delete lines A–B; replace with one expression," or "remove field F and its three writers; the two reads can compute it from G inline." If the cut spans more than a handful of hunks, say so explicitly — that is itself a signal the complexity is structural rather than local.

5. **Estimate the net.** Lines removed vs. lines added. Properties removed. Branches collapsed. Files removed. If the cut is not net-positive on behaviour-preserved-per-line, drop it.

6. **Rank.** Order by `(lines + state + branches removed) ÷ risk`, descending. Cap at 7. A longer list usually means the bottom entries are padding.

## Output format

A single markdown punch list. No intro paragraph. For each entry:

```
### N. <file>:<line range> — <one-line label>

**Load it bears:** <one sentence: what user-visible behaviour breaks if deleted>
**Why it's overweight:** <which lens fails, with the specific signal>
**Cut:** <the smallest concrete change, e.g. "delete X; inline Y into Z; remove UserDefaults key K">
**Net:** −N LOC, −M state, −K branches; risk: low | med | high
```

End with a single line: `Summary: −<total LOC>, −<total state>, −<total branches> across <N> cuts.`

If the codebase is already at its floor and you cannot find at least three honest cuts, say so plainly. Three honest cuts beat seven padded ones.

## What not to produce

- No new abstractions, protocols, services, managers, or coordinators.
- No new tests "for coverage." If a cut removes the code a test exercises, delete the test in the same proposal.
- No new files. Net file count should be flat or negative.
- No "we could later…" — every proposal stands or falls on the codebase as it is today.
- No moving complexity from file A to file B.
- No proposals to add configurability, pluggability, themeing, extensibility, or hooks.
- No new error handling, logging, telemetry, or analytics. The app is local and silent on purpose.
- No "make it more idiomatic Swift" cuts without a behaviour-preserving line-count win.
- No suggestions that revisit anything on README's "Not built" list or PURPOSE's "What this is not" list.

## Don't commit

Leave the working tree clean. This command produces a report, not edits. The user reads it, picks which cuts to make, and makes them by hand or in a follow-up session.
