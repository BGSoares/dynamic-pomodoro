# Feature spec — Loop continuity & window discipline

**Status:** Proposed. Every experience decision below was settled with the owner (§11 records
them); §9 lists the three still open.
**Scope:** four changes — two behavioural (skip → next session, break-end foreground), one
structural (the main window stops being a permanent fixture), one refinement (1-minute duration
steps).

| # | Change | One line |
|---|--------|----------|
| 1 | **Skip auto-start** | Completing the 15-second skip hold starts a 15-second cancellable countdown into the next focus session. |
| 2 | **Break-end foreground** | A break that ends while the screen is *known unlocked* brings the app forward on the idle screen — and deliberately does **not** auto-start anything. |
| 3 | **Window discipline** | The main window exists to take a decision. During a focus session there is no window; the menu bar is the only timer. |
| 4 | **1-minute steps** | The two focus-duration steppers in Settings move a minute at a time instead of five. |

Changes 1 and 2 both live next to
[`SPEC_UNLOCK_AUTOSTART.md`](SPEC_UNLOCK_AUTOSTART.md)'s unlock countdown and reuse its machinery;
that spec stays authoritative for the unlock trigger, which this one does not modify.

---

## §1 Why

**Change 1 — the skip is a decision to keep working, and the app currently ignores it.** Holding
the skip button for 15 seconds is the most deliberate act in the app. What follows it today is
`.idle`: the overlay fades, nothing runs, and the next session starts whenever willpower remembers
the menu bar. The person who just paid 15 seconds to *not* stop is exactly the person who wanted to
be back in a session immediately. The loop's return edge is already assisted after a break the user
walked away from (the unlock countdown); this closes the same edge for the break they refused.

**Change 2 — the app is invisible at the one moment it has something to say.** Breaks end with the
screen locked in the common case, which is what the unlock countdown is built on. The uncommon case
is the one with no handling at all: the user unlocked mid-break, watched or ignored the overlay, and
the break ran out with the machine awake and unlocked. The overlay fades and reveals… the desktop.
Nothing marks the transition except a notification that may be off and a chime that may be muted.
Bringing the window forward makes "the break is over, here's the next session" a thing on screen
rather than a thing to remember.

It must not auto-start, and the reason is specific: an unlock is *proof of presence* (someone typed
a password), which is what licenses the unlock countdown to start a session opt-out. A break ending
proves nothing — the user may have unlocked, glanced at the overlay, and walked away. So this
change surfaces a choice; it never makes one.

**Change 3 — the window outlived its job.** The window is where you start a session and where you
abandon one. Between those two moments it shows a ring that the menu bar already shows, sitting in
⌘-Tab and in the way. PURPOSE principle 5 ("the smallest surface that does the job") argues for the
window appearing when the app needs a decision and disappearing when it doesn't.

**Change 4 — 5-minute granularity is coarser than the curve.**
[`DurationCurve`](Sources/DynamicPomodoro/Logic/DurationCurve.swift) interpolates and rounds to the
nearest minute, so the curve already emits 27- and 33-minute sessions. Only the *bounds* are stuck
on multiples of five, which is an arbitrary limit on the one dial the tool actually respects.

---

## §2 Change 1 — Skip auto-start

### §2.1 Trigger

The completion of a hold-to-skip: [`HoldToSkipButton`](Sources/DynamicPomodoro/Views/HoldToSkipButton.swift)
`onComplete` → `TimerEngine.skipBreak()` → `PomodoroReducer.reduce(.skipBreak)`. Nothing else.

### §2.2 Which "skips" count — exactly one

`SessionLogEntry.Kind.breakSkipped` is written by **two** unrelated paths, and only the first one
triggers this feature:

| Path | Reducer site | Auto-start? |
|---|---|---|
| Hold-to-skip completed | `.skipBreak` case | **Yes** |
| Owed break outlived the 30-minute call cap | `.tick` → `.breakPending` cap branch | **No** |

The cap path is a break the app gave up on while the user was half an hour into a call. A countdown
HUD appearing over that call, on its way to starting a session nobody asked for, is a jump-scare.
That path keeps today's behaviour exactly: go idle, log it, say nothing.

The two paths are already separate branches of the reducer, so the distinction is a matter of which
branch emits the new effect — and is directly unit-testable (§8).

### §2.3 Countdown behaviour

On a completed hold:

1. The break overlay begins its normal 1.5 s fade-out immediately (the existing `.breakRunning →
   .idle` phase sink in `main.swift` — untouched).
2. The countdown HUD from
   [`SPEC_UNLOCK_AUTOSTART.md §5`](SPEC_UNLOCK_AUTOSTART.md) appears over the revealed desktop:
   same panel, same card, same copy, same ring, same position, counting down from
   `autoStartCountdownSeconds` (default 15).
3. **Left alone** → `TimerEngine.startFocus()`, identical in every respect to a button start.
   Per change 3 no window appears; the menu-bar timer is the only sign.
4. **Cancelled** (Esc, or a click on the menu-bar item) → HUD dismisses, the app stays idle, the
   skip stands. The cancel additionally **suppresses the unlock countdown for that same break end**
   (§2.4).

The deadline-based timing and the ~3 s overshoot guard (`UnlockGate.shouldStillFire`) apply
unchanged: if the machine sleeps mid-countdown, nothing starts on wake.

### §2.4 Cancel suppression, and why the effect order matters

`AutoStartService` already records `offeredBreakEnd` when a countdown starts and, on a suppressing
cancel, writes it to `suppressedBreakEnd` — which gate clause G4 checks on every subsequent unlock.
Feeding the skip countdown through the same field gives the decided behaviour for free: cancelling
the skip countdown means locking and unlocking 10 minutes later will *not* re-offer for that break.

This depends on the skip's log entry being written **before** the countdown is offered, since
`offeredBreakEnd` is read from `SessionLogStore.lastBreakEnd()`. Effects are interpreted in array
order, so the `.skipBreak` case must return `.logSession` ahead of the new offer effect. A test
pins the order (§8) — it is load-bearing, not cosmetic.

### §2.5 Edge cases

- **Lock during the skip countdown** — dismiss, no suppression (existing `handleLock` behaviour):
  the user never said no, and a later unlock inside the 20-minute window may still legitimately
  offer. Also rules out a session auto-starting into a locked, empty room.
- **A countdown already running** — impossible in practice (a break was running a moment ago, so
  the unlock gate's G1 could not have fired), but the service's `guard !isCountingDown` covers it.
- **Quit during the countdown** — allowed. `applicationShouldTerminate` blocks only
  `.breakRunning` / `.breakPending`; the phase here is `.idle`, and quitting takes the HUD with it.
- **The skipped break's activity** is logged as today. Nothing about the skip's bookkeeping changes.

---

## §3 Change 2 — Break-end foreground

### §3.1 Knowing whether the screen is unlocked

The app already observes `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` inside
`UnlockAutoStartService`. Change 2 needs the same signal as *state* rather than as an event, and
change 1 leaves two consumers, so the observation moves into one place:

```swift
enum ScreenLockState { case unknown, locked, unlocked }
```

`unknown` is the launch value and is **never** treated as unlocked. That is the decided behaviour:
foreground only on a positively observed unlock. Consequences, accepted:

- The app launched mid-break, or restarted since the last lock → no foregrounding for that break.
- A Mac configured never to require a password posts neither notification → the feature is inert
  there, exactly as the unlock countdown already is.

The alternative (assume unlocked until told otherwise) would front a window onto a locked screen,
where it is invisible, does nothing, and then sits there competing with the unlock countdown on the
next unlock. Not worth the coverage it buys.

### §3.2 Gate

At break completion, foreground iff **both**:

| # | Condition | Rationale |
|---|-----------|-----------|
| F1 | The break ended by **completing** (`completeBreak`), not by a skip or the call cap | A skipped break is change 1's business; the call-cap break is nobody's (§2.2). |
| F2 | `ScreenLockState == .unlocked` | The whole point: the screen is awake and someone unlocked it. `.locked` is the common case and belongs to the unlock countdown; `.unknown` is not evidence (§3.1). |

There is no time window and no suppression: the trigger is a single instantaneous transition, so
neither can apply.

### §3.3 What comes forward

The existing main window, activated, on the idle screen — `openMainWindow()`, which already ends in
`NSApp.activate(ignoringOtherApps:)`. `MainWindowView` routes on phase, and the phase is `.idle` by
then, so the content is `IdleView`: *"Ready / Next session: 32 min"* and a **Start focus** button
already wired to `.keyboardShortcut(.return)`. One keypress starts the session; doing nothing
starts nothing.

No new view, no new window, no countdown, no auto-start.

The break-complete chime and the "Break complete — Ready when you are" notification are unchanged
and still fire regardless of lock state.

**Ordering note for the implementer:** the overlay's fade-out (1.5 s, shielding level) is still
running when the window is presented, so the window is revealed *by* the fade rather than popping
over it — the nicer transition, and the reason to present immediately rather than waiting for the
fade to complete. Worth confirming by eye (§8) that the main window ends up key once the shielding
panels order out.

### §3.4 Relationship with the unlock countdown — deliberately none

If the user is fronted the window, walks away, the Mac locks itself, and they return and unlock
inside the 20-minute window, the unlock countdown offers and auto-starts as it does today. That is
the decided behaviour: the later unlock is fresh proof of presence, and nothing about the earlier
foregrounding contradicts it. `UnlockGate` is not modified by this change, and the foreground path
writes nothing to `suppressedBreakEnd`.

### §3.5 Edge cases

- **User is in another app's full-screen Space** — activation may switch Spaces. Accepted: the
  break overlay covered that Space thirty seconds ago; this is less disruptive than what preceded it.
- **Break completed by the wake-tick after sleep** — the machine woke, so a lock/unlock pair almost
  certainly preceded it; if the state says unlocked, the user is there and the window is correct.
- **Screen-sharing / presenting** — the app comes forward. Same exposure the full-screen break
  overlay already has, and no more.

---

## §4 Change 3 — Window discipline

### §4.1 The rule

> The main window appears when the app needs a decision from the user, and gets out of the way when
> it doesn't. The menu bar is the timer.

### §4.2 Per-phase behaviour

| Moment | Window | Why |
|---|---|---|
| Launch (idle) | **Opens** (unchanged) | You launched the app to start something. |
| Focus starts — *any* path: window button, menu-bar "Start focus", skip countdown (§2), unlock countdown | **Hides** (`orderOut`) | The change. The menu-bar `F 24:59` is the whole UI for a running session. |
| During focus, user picks menu bar → **Open** | **Opens**, shows `FocusView` (ring + Abandon) | Unchanged view; this is the abandon path (§4.3). |
| A window opened mid-session | **Stays until the user closes it** | No auto-close timers, no close-on-deactivate. A window you opened is a window you keep. |
| Focus ends, break starts | Overlay takes over; window untouched | `BreakMirrorView` still mirrors state if a window happens to be open. |
| Focus ends **on a call** → `.breakPending` | **Opens** | The "Start break now" override lives there, and the app is asking a question. |
| Break completes, screen unlocked | **Opens** (change 2) | Same rule. |
| Break completes, screen locked | Nothing | Nobody is there; the unlock countdown handles the return. |
| Break skipped | Nothing | §2 starts a session instead, and a session means no window. |

The one behavioural removal in `main.swift`: `menuStartFocus()` no longer calls `openMainWindow()`.
Starting from the menu bar now starts a session and nothing else, which is the point of the change.

### §4.3 Abandon stays in the window

No "Abandon session" menu-bar item is added. Abandoning is menu bar → **Open** → **Abandon
session** → confirm — four interactions guarding a destructive, irreversible discard, in the same
place it has always been. This deliberately keeps abandon *more* expensive than start, matching the
asymmetry PURPOSE principle 4 builds everywhere else.

### §4.4 Nothing else moves

`MainWindowView`'s routing, `MainWindowDelegate`'s hide-instead-of-destroy behaviour, the Settings
window, and the status menu's items are all unchanged.

---

## §5 Change 4 — 1-minute duration steps

In [`SettingsView`](Sources/DynamicPomodoro/Views/SettingsView.swift), on the two "Focus duration"
steppers only:

| | Before | After |
|---|---|---|
| Minimum stepper | `in: 5...60, step: 5` | `in: 5...60, step: 1` |
| Maximum stepper | `in: 10...90, step: 5` | `in: 10...90, step: 1` |
| Min/max separation guard (`min ≤ max − 5`, `max ≥ min + 5`) | 5 min | **5 min — unchanged** |
| Workday Start/End steppers | `step: 15` | **`step: 15` — unchanged** |

So 22/37 becomes settable; 38/40 still snaps to 35/40. The guard staying at five while the step
drops to one is a decided trade-off, not an oversight: it keeps the curve's span meaningfully wide
without constraining where that span sits.

`Settings.init`'s clamps already express the same rule arithmetically (`clampedMax`,
`minFocusMinutes`) and need no change — they never assumed multiples of five.

---

## §6 Architecture & file map

Pure decisions in `Logic/`, effectful glue in `Services/`, AppKit wiring in `main.swift`.

| File | Change |
|------|--------|
| `Logic/ScreenLockState.swift` | **New.** The three-case enum (§3.1). Pure, trivially testable, no AppKit. |
| `Services/ScreenLockMonitor.swift` | **New.** `@MainActor`, owns the two `DistributedNotificationCenter` observers, publishes `state: ScreenLockState`, and exposes an unlock hook for the auto-start service. Absorbs the observer code currently inside `UnlockAutoStartService`. |
| `Services/UnlockAutoStartService.swift` → `Services/AutoStartService.swift` | **Renamed** (it now serves two triggers). Loses its observers to the monitor; gains `offerAfterSkip(now:)` beside `handleUnlock(now:)`, both funnelling into the existing private `startCountdown(now:breakEnd:)`. The skip path needs no `UnlockGate` clauses — the reducer already proved the state — beyond the `isCountingDown` idempotency guard. `CountdownHUDView`'s `@ObservedObject` type follows the rename. |
| `Core/PomodoroCore.swift` | Three new `PomodoroEffect` cases: `.offerAutoStart`, `.presentMainWindow(requiresUnlocked: Bool)`, `.hideMainWindow`. Emitted from: `.skipBreak` (after `.logSession`, §2.4); `completeBreak` → `.presentMainWindow(requiresUnlocked: true)`; both `.breakPending` entry points → `.presentMainWindow(requiresUnlocked: false)`; `.startFocus` → `.hideMainWindow`. The `.breakPending` cap branch emits **none** of them (§2.2). |
| `Services/TimerEngine.swift` | Interprets the three effects. `.presentMainWindow(requiresUnlocked:)` consults an injected `lockProbe: () -> ScreenLockState` — the same seam idiom as the existing `callProbe` — and forwards to injected window/offer closures (default no-ops, so tests and previews stay AppKit-free). |
| `main.swift` | Constructs `ScreenLockMonitor` before `TimerEngine` (a `lazy var timer` keeps initialisation order legal) and injects the probe plus the closures: present → `openMainWindow()`, hide → `mainWindow?.orderOut(nil)`, offer → `autoStart.offerAfterSkip()`. Drops `openMainWindow()` from `menuStartFocus()` (§4.2). Routes the monitor's unlock hook to `autoStart.handleUnlock()`. The DEBUG "Simulate unlock (test)" item stays. |
| `Views/SettingsView.swift` | `step: 5` → `step: 1`, twice (§5). |
| `Tests/.../PomodoroCoreTests.swift` | Extended — the effect-emission matrix, §8. |
| `Tests/.../ScreenLockStateTests.swift` | **New.** Small; §8. |
| `README.md` | In the implementing PR: architecture-tree entries for the two new files and the rename, plus "Spec implementation notes" bullets. |

`UnlockGate` and `SPEC_UNLOCK_AUTOSTART.md`'s behaviour are untouched. The rename is the only churn
this spec imposes on the existing feature, and it is worth it: `UnlockAutoStartService` would be a
lie the moment a skip can drive it.

---

## §7 Testing

**Unit (swift-testing, synthetic dates, no timers, no AppKit):**

- `PomodoroCoreTests`, effect emission — the heart of all three behavioural changes:
  - `.skipBreak` from `.breakRunning` emits `.offerAutoStart`, **positioned after** `.logSession`
    (assert on the array order, not just membership — §2.4).
  - `.tick` past `breakPendingCapSeconds` logs `breakSkipped` and emits **no** `.offerAutoStart`
    (§2.2) — the single most important negative test in this spec.
  - Break completing emits `.presentMainWindow(requiresUnlocked: true)`.
  - `.startFocus` emits `.hideMainWindow`; entering `.breakPending` (both the tick path and the
    fast-forward path) emits `.presentMainWindow(requiresUnlocked: false)`.
  - `.skipBreak` while `.idle` / `.focus` still emits nothing at all.
- `ScreenLockStateTests`: `.unknown` and `.locked` do not satisfy F2; `.unlocked` does.
- Existing `UnlockGateTests` and `SessionLogStoreTests` must pass **unchanged** — the proof that
  the unlock countdown's contract was not disturbed.

**Manual checklist (real machine, DEBUG build):**

1. Break running → hold skip to completion → overlay fades, HUD counts 15 → focus starts, **no
   window appears**, menu bar shows `F …`.
2. Same, but press Esc mid-countdown → idle, no session. Lock and unlock inside 20 min → **no**
   offer (suppression, §2.4). Complete a full cycle → offers again.
3. Same, but click the menu-bar item mid-countdown → cancels, menu does not open; menu works again
   after.
4. Start focus → window disappears. Menu bar → Open → focus ring + Abandon. Close it; open it
   again; it never closes itself. Abandon → confirm → idle screen.
5. Menu bar → "Start focus" from idle → session starts, no window opens.
6. Break running, screen unlocked (unlock during the break), let it run out → overlay fades and the
   main window is forward on the idle screen; **nothing auto-starts**; Return starts a session and
   the window disappears.
7. Same, but stay locked through the end of the break → no window; unlock → the usual countdown.
8. Relaunch the app mid-break, let the break end while unlocked → no foregrounding (`.unknown`,
   §3.1). Verifies the strict rule rather than a lucky default.
9. `DP_FAKE_ON_CALL=1`, fast-forward a focus session → `.breakPending` and the window comes forward
   with "Start break now".
10. Settings → focus steppers move 1 min at a time; drag the minimum up to the maximum and confirm
    it stops 5 below; workday steppers still jump 15 min.

---

## §8 Non-goals & accepted trade-offs

**Non-goals:**

- **No new settings.** The skip countdown reuses `autoStartCountdownSeconds`; the four visible
  settings stay four.
- **No auto-start after a *completed* break.** That remains the unlock countdown's job, gated on
  proof of presence. Change 2 explicitly stops short of it.
- **No third countdown exit** ("start in 5 min", snooze) and no click-to-confirm on the HUD.
- **No new menu-bar items**, including for abandon (§4.3).
- **No log-schema change.** An auto-started session is indistinguishable from a manual one by
  design; re-entry latency stays derivable from existing timestamps.
- **No auto-close behaviour for a window the user opened**, by any timer or focus rule.

**Accepted trade-offs:**

- A skip cancelled at second 14 costs the user 14 seconds of nothing. The alternative — starting
  instantly — removes the escape hatch for a hold that completed by accident (a leaning wrist, a
  stuck trackpad), and that hold is 15 seconds of pressure, not a click.
- Foregrounding at break end can pull the user out of a full-screen Space (§3.5).
- A Mac that never locks gets neither the unlock countdown nor the break-end foreground (§3.1).
- Abandoning now costs an extra window-open. Deliberate (§4.3).
- The `UnlockAutoStartService` → `AutoStartService` rename dirties a file the existing spec names
  by path; `SPEC_UNLOCK_AUTOSTART.md` gets a one-line pointer in the implementing PR rather than a
  rewrite.

---

## §9 Open questions for the implementing PR

1. **Should cancelling the *unlock* countdown also present the main window?** Today it leaves the
   user idle with no visible app, which sits oddly beside change 3's rule ("a window when the app
   needs a decision"). Recommendation: **no** — cancelling is the user saying "not now", and
   answering that with a window is arguing back. Flagged because it is the one place the new rule
   and the old feature disagree.
2. **Should the HUD copy differ for the skip path?** It currently reads *"Focus starts in 12s /
   Esc or click the menu bar icon to cancel"*, which is accurate for both triggers.
   Recommendation: **no** — identical copy, one card to recognise.
3. **Should `.breakPending` foregrounding be suppressed while screen-sharing?** Out of scope here
   (the break overlay has the same exposure today), but it is the one case where the new window
   rule fires during a call.

---

## §10 PURPOSE alignment

- **Serves the core loop (guide #1).** Changes 1 and 2 both act on the loop's return edge — the
  only transition the app still leaves entirely to willpower. Change 1 covers the break you refused;
  change 2 covers the break you were present for; the unlock countdown already covered the break you
  walked away from. Together the three exhaust the ways a break can end with the user reachable.
- **Friction in the right places (principle 4), stated honestly.** Change 1 can be read as
  rewarding a skip. The counter is that it changes nothing about the skip's *price* — still 15
  seconds of hold, still the nudge line, still logged as skipped — and changes only what follows:
  work, rather than a free-floating idle state that the skip was never asking for. Nothing here
  makes skipping a break cheaper, which is the actual test guide #2 sets.
- **Surface area (principle 5).** Net: one new enum, one small monitor service, one rename, three
  effect cases — and one *fewer* persistent window. No new settings, no new views, no new windows,
  no new menu items. Change 3 is a subtraction.
- **Local, private, native (principle 6).** No new permissions, no polling, no network. The lock
  signal is the same pair of distributed notifications already in use, now observed once instead of
  once per consumer.
- **Not configurable infinitely.** Change 4 refines an existing dial rather than adding one; the
  personalisation surface is still exactly four settings.

---

## §11 Decision log

Recorded because §1's reasoning reconstructs *why*, not *who decided*. All answered by the owner
before this spec was written.

| Question | Decision |
|---|---|
| How should the next session begin after a completed skip hold? | 15-second cancellable countdown (not immediate, not a prompt). |
| What is on screen behind the skip countdown? | The overlay fades at once; the HUD floats over the desktop. |
| What is on screen after the skip auto-start fires? | Nothing — menu bar only. |
| Does cancelling the skip countdown also suppress the unlock countdown for that break end? | Yes. |
| Does the 30-minute call-cap skip also auto-start? | No — hold-to-skip only. |
| What comes forward when a break ends unlocked? | The main window, activated, on the idle screen. |
| Does that foregrounding consume the unlock countdown's offer for that break end? | No — the unlock countdown is unchanged. |
| What if lock state was never observed? | Do nothing. Observed unlock only. |
| How is a session abandoned once there is no window? | Open the window from the menu bar; no new menu item. |
| When does a window opened mid-session close? | Only when the user closes it. |
| Does the app still open a window at launch? | Yes. |
| Does the window come forward when a break is deferred by a call? | Yes. |
| What else changes in Settings? | Nothing — the focus steppers only; workday steps and the 5-minute min/max gap stay. |
