# Feature spec — Loop continuity, window discipline, meeting silence

**Status:** Proposed. Every experience decision below was settled with the owner (§12 records
them); §10 lists what is still open.
**Scope:** five changes — two behavioural (skip → next session, break-end foreground), one
structural (the main window stops being a permanent fixture), one refinement (1-minute duration
steps), and one that constrains all of the above (nothing on screen or audible during a call).

| # | Change | One line |
|---|--------|----------|
| 1 | **Skip auto-start** | Completing the 15-second skip hold starts a 15-second cancellable countdown into the next focus session. |
| 2 | **Break-end foreground** | A break that ends while the screen is *known unlocked* brings the app forward on the idle screen — and deliberately does **not** auto-start anything. |
| 3 | **Window discipline** | The main window exists to take a decision. During a focus session there is no window; the menu bar is the only timer. |
| 4 | **1-minute steps** | The two focus-duration steppers in Settings move a minute at a time instead of five. |
| 5 | **Meeting silence** | While a call is live the app shows nothing and plays nothing. New PURPOSE principle 7; overrides changes 1–3 wherever they conflict. |

Changes 1 and 2 sit next to [`SPEC_UNLOCK_AUTOSTART.md`](SPEC_UNLOCK_AUTOSTART.md)'s unlock
countdown and reuse its machinery. That spec stays authoritative for the unlock trigger, with one
exception: change 5 reverses its "call state is deliberately not a gate input" line (§6.4).

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
has no handling at all: the user unlocked mid-break, watched or ignored the overlay, and the break
ran out with the machine awake and unlocked. The overlay fades and reveals… the desktop. Nothing
marks the transition except a notification that may be off and a chime that may be muted.

It must not auto-start, and the reason is specific: an unlock is *proof of presence* (someone typed
a password), which is what licenses the unlock countdown to start a session opt-out. A break ending
proves nothing — the user may have unlocked, glanced at the overlay, and walked away. So this
change surfaces a choice; it never makes one.

**Change 3 — the window outlived its job.** The window is where you start a session and where you
abandon one. Between those two moments it shows a ring the menu bar already shows, sitting in ⌘-Tab
and in the way. PURPOSE principle 5 ("the smallest surface that does the job") argues for a window
that appears when the app needs a decision and disappears when it doesn't.

**Change 4 — 5-minute granularity is coarser than the curve.**
[`DurationCurve`](Sources/DynamicPomodoro/Logic/DurationCurve.swift) interpolates and rounds to the
nearest minute, so the curve already emits 27- and 33-minute sessions. Only the *bounds* were stuck
on multiples of five, an arbitrary limit on the one dial the tool actually respects.

**Change 5 — a shared screen puts this app in front of other people.** A full-screen "TAKE A BREAK"
card, or a countdown HUD, landing in someone else's meeting window is the worst thing this tool
could do. The app already withholds breaks during calls; changes 1–3 would have added three new
ways to put something on screen, so the constraint gets stated as a principle and applied to all of
them at once. Written up as PURPOSE principle 7.

---

## §2 Change 1 — Skip auto-start

### §2.1 Trigger

The completion of a hold-to-skip: [`HoldToSkipButton`](Sources/DynamicPomodoro/Views/HoldToSkipButton.swift)
`onComplete` → `TimerEngine.skipBreak()` → `PomodoroReducer.reduce(.skipBreak)`. Nothing else.

### §2.2 Which "skips" count — exactly one

`SessionLogEntry.Kind.breakSkipped` is written by **two** unrelated paths, and only the first
triggers this feature:

| Path | Reducer site | Auto-start? |
|---|---|---|
| Hold-to-skip completed | `.skipBreak` case | **Yes** |
| Owed break outlived the 30-minute call cap | `.tick` → `.breakPending` cap branch | **No** |

The cap path is a break the app gave up on while the user was half an hour into a call. A countdown
HUD appearing over that call, on its way to starting a session nobody asked for, is a jump-scare —
and change 5 forbids it outright. That path keeps today's behaviour exactly: go idle, log it, say
nothing.

The two paths are already separate reducer branches, so the distinction is a matter of which branch
emits the new effect, and is directly unit-testable (§8).

### §2.3 Countdown behaviour

On a completed hold, **with no call live** (§6):

1. The break overlay begins its normal 1.5 s fade-out immediately (the existing `.breakRunning →
   .idle` phase sink in `main.swift` — untouched).
2. The countdown HUD from [`SPEC_UNLOCK_AUTOSTART.md §5`](SPEC_UNLOCK_AUTOSTART.md) appears over
   the revealed desktop: same panel, same card, **same copy**, same ring, same position, counting
   down from `autoStartCountdownSeconds` (default 15).
3. **Left alone** → `TimerEngine.startFocus()`, identical in every respect to a button start. Per
   change 3 no window appears; the menu-bar timer is the only sign.
4. **Cancelled** (Esc, or a click on the menu-bar item) → HUD dismisses, the skip stands, the app
   goes idle **and presents the main window** on the idle screen (§4.2). The cancel additionally
   suppresses the unlock countdown for that same break end (§2.4).

If a call *is* live when the hold completes, none of this happens: no HUD, no session, no window.
The app goes idle exactly as it does today (§6.3).

The deadline-based timing and the ~3 s overshoot guard (`UnlockGate.shouldStillFire`) apply
unchanged: if the machine sleeps mid-countdown, nothing starts on wake.

### §2.4 Cancel suppression, and why the effect order matters

`AutoStartService` already records `offeredBreakEnd` when a countdown starts and, on a suppressing
cancel, writes it to `suppressedBreakEnd` — which gate clause G4 checks on every subsequent unlock.
Feeding the skip countdown through the same field gives the decided behaviour for free: cancelling
the skip countdown means locking and unlocking ten minutes later will *not* re-offer for that break.

This depends on the skip's log entry being written **before** the countdown is offered, since
`offeredBreakEnd` is read from `SessionLogStore.lastBreakEnd()`. Effects are interpreted in array
order, so the `.skipBreak` case must return `.logSession` ahead of the offer effect. A test pins the
order (§8) — it is load-bearing, not cosmetic.

### §2.5 Edge cases

- **Lock during the countdown** — dismiss, no suppression (existing `handleLock` behaviour): the
  user never said no, and a later unlock inside the 20-minute window may still legitimately offer.
  Also rules out a session auto-starting into a locked, empty room.
- **A countdown already running** — impossible in practice (a break was running a moment ago, so
  the unlock gate's G1 could not have fired), but `guard !isCountingDown` covers it.
- **Quit during the countdown** — allowed. `applicationShouldTerminate` blocks only
  `.breakRunning` / `.breakPending`; the phase here is `.idle`, and quitting takes the HUD with it.
- **The skipped break's activity** is logged as today. Nothing about the skip's bookkeeping changes.

---

## §3 Change 2 — Break-end foreground

### §3.1 Knowing whether the screen is unlocked

The app already observes `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` inside
`UnlockAutoStartService`. Change 2 needs that signal as *state* rather than as an event, and change
1 leaves two consumers, so the observation moves into one place:

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

At break completion, foreground iff **all three**:

| # | Condition | Rationale |
|---|-----------|-----------|
| F1 | The break ended by **completing**, not by a skip or the call cap | A skipped break is change 1's business; the call-cap break is nobody's (§2.2). |
| F2 | `ScreenLockState == .unlocked` | The whole point: the screen is awake and someone unlocked it. `.locked` is the common case and belongs to the unlock countdown; `.unknown` is not evidence (§3.1). |
| F3 | No live call | Principle 7 (§6). A break can only be running during a call if the call started mid-break, but that is exactly the case that matters. |

There is no time window and no suppression: the trigger is a single instantaneous transition, so
neither can apply.

### §3.3 What comes forward

The existing main window, activated, on the idle screen — `openMainWindow()`, which already ends in
`NSApp.activate(ignoringOtherApps:)`. `MainWindowView` routes on phase, and the phase is `.idle` by
then, so the content is `IdleView`: *"Ready / Next session: 32 min"* and a **Start focus** button
already wired to `.keyboardShortcut(.return)`. One keypress starts the session; doing nothing starts
nothing.

No new view, no new window, no countdown, no auto-start.

The "Break complete — Ready when you are" notification is unchanged. The chime is unchanged *except*
during a call (§6.2).

**Ordering note for the implementer:** the overlay's fade-out (1.5 s, shielding level) is still
running when the window is presented, so the window is revealed *by* the fade rather than popping
over it — the nicer transition, and the reason to present immediately rather than waiting for the
fade to finish. Worth confirming by eye (§8) that the main window ends up key once the shielding
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

---

## §4 Change 3 — Window discipline

### §4.1 The rule

> The main window appears when the app needs a decision from the user, and gets out of the way when
> it doesn't. The menu bar is the timer. Nothing appears during a call (§6).

### §4.2 Per-phase behaviour

| Moment | Window | Why |
|---|---|---|
| Launch (idle) | **Opens** (unchanged) | You launched the app to start something. |
| Focus starts — *any* path: window button, menu-bar "Start focus", skip countdown, unlock countdown | **Hides** (`orderOut`) | The change. The menu-bar `F 24:59` is the whole UI for a running session. |
| During focus, menu bar → **Open** | **Opens**, shows `FocusView` (ring + Abandon) | Unchanged view; this is the abandon path (§4.3). |
| A window opened mid-session | **Stays until the user closes it** | No auto-close timers, no close-on-deactivate. A window you opened is a window you keep. |
| Focus ends, break starts | Overlay takes over; window untouched | `BreakMirrorView` still mirrors state if a window happens to be open. |
| Focus ends **on a call** → `.breakPending` | **Nothing** | Principle 7 (§6). Reverses an earlier decision; the override moves to the menu bar (§4.3). |
| Break completes, screen unlocked, no call | **Opens** (change 2) | Same rule. |
| Break completes, screen locked | Nothing | Nobody is there; the unlock countdown handles the return. |
| Break skipped | Nothing, then a countdown | §2 starts a session instead, and a session means no window. |
| Either countdown **cancelled** | **Opens** on the idle screen | You just declined an automatic start, which means the next start is manual — so the app puts the button in front of you. |

Two behavioural removals in `main.swift`: `menuStartFocus()` no longer calls `openMainWindow()`
(starting from the menu bar now starts a session and nothing else, which is the point), and the
`.breakPending` phase no longer brings the window forward.

### §4.3 One new menu-bar item, and it isn't abandon

Principle 7 removed the only surface that carried the "Start break now" override — the
`.breakPending` window, which by definition appears while a call is live. The override moves to the
status menu:

- **"Start break now"**, in the status menu above "Start focus", enabled only in `.breakPending`
  (hidden or disabled otherwise, implementer's choice — `validateMenuItem` is the idiomatic route).
- Nothing appears on screen when a break is deferred: the notification and the menu bar's `B …`
  are the signal, and the menu item is there when the user goes looking.

**Abandon gains no such item.** Abandoning is menu bar → **Open** → **Abandon session** → confirm:
four interactions guarding a destructive, irreversible discard, in the same place it has always
been. This keeps abandon *more* expensive than start, matching the asymmetry PURPOSE principle 4
builds everywhere else. "Start break now" earns its item because the principle took its window away;
abandon never had that problem.

### §4.4 Nothing else moves

`MainWindowView`'s routing, `MainWindowDelegate`'s hide-instead-of-destroy behaviour, the Settings
window, and the rest of the status menu are unchanged.

---

## §5 Change 4 — 1-minute duration steps

In [`SettingsView`](Sources/DynamicPomodoro/Views/SettingsView.swift), on the two "Focus duration"
steppers only:

| | Before | After |
|---|---|---|
| Minimum stepper | `in: 5...60, step: 5` | `in: 5...60, step: 1` |
| Maximum stepper | `in: 10...90, step: 5` | `in: 10...90, step: 1` |
| Min/max separation guard (`max ≥ min + 5`) | 5 min | **5 min — unchanged** |
| Workday Start/End steppers | `step: 15` | **`step: 15` — unchanged** |

So 22/37 becomes settable; 38/40 still snaps to 35/40. The guard staying at five while the step
drops to one is a decided trade-off, not an oversight: it keeps the curve's span meaningfully wide
without constraining where that span sits.

`Settings.init`'s clamps already express the same rule arithmetically (`clampedMax`,
`minFocusMinutes`) and need no change — they never assumed multiples of five.

---

## §6 Change 5 — Meeting silence

> While a call is live, the app puts nothing on screen and makes no sound.
> — PURPOSE principle 7

### §6.1 The signal, and its blind spot

`CallDetectionService.isOnCall()` — CoreAudio input-device state, already in the codebase, no
capture, no permission prompt. Every meeting app holds the input stream open for the duration of a
call, muted or not.

**macOS exposes no public way to know whether the screen is being shared.** ScreenCaptureKit lets an
app capture; nothing lets an app ask "is someone capturing me". So the trigger is *any live call*,
which is deliberately broader than the screen-share case that motivated the principle: over-
suppressing costs a missed pomodoro, under-suppressing costs an overlay in a client call. The
asymmetry decides it. The blind spot is recorded here so a future macOS release can narrow it.

The `DP_FAKE_ON_CALL` DEBUG override currently lives in `TimerEngine.defaultCallProbe`. It moves
into `CallDetectionService.isOnCall()` itself so that every consumer — reducer, auto-start service,
window presenter — honours one seam, and the manual checklist below is runnable.

### §6.2 What is suppressed

| Surface | On a call |
|---|---|
| Main window presentation (break end, countdown cancel) | Suppressed |
| Countdown HUD, both triggers (skip and unlock) | Suppressed — and no session starts (§6.3) |
| `.breakPending` window | Never presented at all (§4.3) |
| Focus-complete and break-complete chimes | Suppressed |
| Break overlay | Already prevented — breaks defer during calls (§6.5) |

**Not suppressed:** notifications (macOS Focus modes already own that decision, and "Focus complete
— break starts when your call ends" is the only signal that a break is now owed); the menu-bar
title; the Settings window; and **any window the user opens themselves** from the menu bar. The rule
is that the app never puts a window on screen the user didn't ask for — not that windows become
unreachable.

Suppression is checked at the moment of presentation, not latched. A call that ends never
retroactively releases a suppressed HUD or chime.

### §6.3 A suppressed countdown starts nothing

When a call suppresses a countdown, the app does not silently start the session. It goes idle and
says nothing. The reasoning: a session may have no visible surface, but a *countdown* is an offer,
and starting the thing that was offered without ever showing the offer removes the cancel path from
a decision the user never saw. Nothing in this app begins without the chance to stop it.

Consequence: the offer is dropped, not queued. No suppression flag is written, so a later unlock
inside the 20-minute window may still offer — the same semantics as a lock-dismissed countdown.

### §6.4 This overrides `SPEC_UNLOCK_AUTOSTART.md` §3

That spec says: *"Call state is deliberately not a gate input: focus sessions may start during calls
today (only break starts defer), and the countdown changes nothing about that."* Principle 7
reverses it. The unlock countdown is now call-gated like everything else, and the implementing PR
amends that line rather than leaving two specs disagreeing.

Note the narrowness of the reversal: a focus session *started by hand* during a call is still fine
and always was. What is forbidden is the app putting the offer on screen.

### §6.5 Scope boundary: the break overlay

The overlay is not modified by this spec. It cannot appear during a call — the existing deferral
holds breaks in `.breakPending` — and a call starting *mid-break* is close to impossible in practice,
since the screen locks 30 seconds in. Tearing down a running overlay when a call begins would also
hand back a friction-free break skip to anyone who joins a call, which principle 4 forbids. Recorded
as a boundary rather than an oversight; §10 keeps it open.

---

## §7 Architecture & file map

Pure decisions in `Logic/`, effectful glue in `Services/`, AppKit wiring in `main.swift`.

Call-suppression is **pure**: the reducer already receives `isOnCall`, so it simply omits the
effects rather than having the interpreter drop them — which keeps every clause of change 5
unit-testable with the existing synthetic-date harness. Lock state, which the reducer has no
business knowing, is checked interpreter-side.

| File | Change |
|------|--------|
| `Logic/ScreenLockState.swift` | **New.** The three-case enum (§3.1). Pure, no AppKit. |
| `Services/ScreenLockMonitor.swift` | **New.** `@MainActor`, owns the two `DistributedNotificationCenter` observers, publishes `state: ScreenLockState`, exposes an unlock hook. Absorbs the observer code currently inside `UnlockAutoStartService`. |
| `Services/UnlockAutoStartService.swift` → `Services/AutoStartService.swift` | **Renamed** (it now serves two triggers). Loses its observers to the monitor; gains `offerAfterSkip(now:)` beside `handleUnlock(now:)`, both funnelling into the existing private `startCountdown(now:breakEnd:)`. `handleUnlock` gains a `CallDetectionService.isOnCall()` guard (§6.4); the skip path needs none, since the reducer already applied it. Cancel now also calls the window presenter. `CountdownHUDView`'s `@ObservedObject` type follows the rename. |
| `Core/PomodoroCore.swift` | Three new `PomodoroEffect` cases: `.offerAutoStart`, `.presentMainWindow`, `.hideMainWindow`. Emitted from `.skipBreak` (after `.logSession`, §2.4), `completeBreak`, and `.startFocus` respectively. All three, plus both chime effects, are omitted when `isOnCall` (§6.2). The `.breakPending` branches emit no window effect at all (§4.3). |
| `Services/TimerEngine.swift` | Interprets the three new effects by forwarding to injected closures (`onPresentMainWindow`, `onHideMainWindow`, `onOfferAutoStart`), defaulting to no-ops so tests and previews stay AppKit-free. No lock probe here — the delegate owns that check. |
| `Services/CallDetectionService.swift` | Absorbs the `DP_FAKE_ON_CALL` DEBUG override from `TimerEngine.defaultCallProbe` (§6.1). |
| `main.swift` | Constructs `ScreenLockMonitor` before `TimerEngine` (a `lazy var timer` keeps initialisation order legal); routes the monitor's unlock hook to `autoStart.handleUnlock()`. Adds `presentMainWindow(requireUnlocked:)` — call-gated always, lock-gated for the break-end path — and wires the engine's closures to it. Adds the "Start break now" status-menu item (§4.3). Drops `openMainWindow()` from `menuStartFocus()`. The DEBUG "Simulate unlock (test)" item stays. |
| `Views/SettingsView.swift` | `step: 5` → `step: 1`, twice (§5). |
| `PURPOSE.md` | Principle 7 (§6). **Landed with this spec**, not deferred to the implementing PR — it governs more than this feature set. |
| `SPEC_UNLOCK_AUTOSTART.md` | One-line amendment to §3's call-state sentence (§6.4), in the implementing PR. |
| `Tests/.../PomodoroCoreTests.swift` | Extended — the effect-emission matrix, §8. |
| `Tests/.../ScreenLockStateTests.swift` | **New.** Small; §8. |
| `README.md` | In the implementing PR: architecture-tree entries for the two new files and the rename, plus "Spec implementation notes" bullets. |

`UnlockGate` is untouched. The rename is the only churn this spec imposes on the existing feature's
code, and it is worth it: `UnlockAutoStartService` becomes a lie the moment a skip can drive it.

---

## §8 Testing

**Unit (swift-testing, synthetic dates, no timers, no AppKit):**

- `PomodoroCoreTests`, effect emission — the heart of changes 1, 2, 3 and 5:
  - `.skipBreak` from `.breakRunning` emits `.offerAutoStart`, **positioned after** `.logSession`
    (assert array order, not just membership — §2.4).
  - `.tick` past `breakPendingCapSeconds` logs `breakSkipped` and emits **no** `.offerAutoStart`
    (§2.2) — the single most important negative test in this spec.
  - Break completing emits `.presentMainWindow`; `.startFocus` emits `.hideMainWindow`; entering
    `.breakPending` (both the tick and fast-forward paths) emits **neither**.
  - With `isOnCall: true`: `.skipBreak` emits no `.offerAutoStart`, break completion emits neither
    `.presentMainWindow` nor `.playBreakCompleteChime`, and focus completion emits no
    `.playFocusCompleteChime` — while the `.logSession` entries in every one of those cases are
    **unchanged** (silence must not cost bookkeeping).
  - `.skipBreak` while `.idle` / `.focus` still emits nothing at all.
- `ScreenLockStateTests`: `.unknown` and `.locked` do not satisfy F2; `.unlocked` does.
- Existing `UnlockGateTests` and `SessionLogStoreTests` must pass **unchanged** — the proof that the
  unlock countdown's own contract was not disturbed.

**Manual checklist (real machine, DEBUG build):**

1. Break running → hold skip to completion → overlay fades, HUD counts 15 → focus starts, **no
   window appears**, menu bar shows `F …`.
2. Same, but press Esc mid-countdown → **the main window opens on the idle screen**. Lock and unlock
   inside 20 min → **no** offer (suppression, §2.4). Complete a full cycle → offers again.
3. Same, but click the menu-bar item mid-countdown → cancels, window opens, menu does not open on
   that click; menu works again after.
4. Start focus → window disappears. Menu bar → Open → focus ring + Abandon. Close it; open it again;
   it never closes itself. Abandon → confirm → idle screen.
5. Menu bar → "Start focus" from idle → session starts, no window opens.
6. Break running, screen unlocked, let it run out → overlay fades and the main window is forward on
   the idle screen; **nothing auto-starts**; Return starts a session and the window disappears.
7. Same, but stay locked through the end of the break → no window; unlock → the usual countdown.
8. Relaunch the app mid-break, let the break end while unlocked → no foregrounding (`.unknown`,
   §3.1). Verifies the strict rule rather than a lucky default.
9. `DP_FAKE_ON_CALL=1`, fast-forward a focus session → `.breakPending`, **no window**, no chime;
   "Start break now" is enabled in the status menu and starts the break.
10. `DP_FAKE_ON_CALL=1`, break running → hold skip → **nothing at all**: no HUD, no session, no
    window, app idle (§6.3).
11. `DP_FAKE_ON_CALL=1`, "Simulate unlock (test)" with a fresh break end → no HUD (§6.4). Unset the
    variable, simulate again → HUD appears.
12. Settings → focus steppers move 1 min at a time; drag the minimum up to the maximum and confirm
    it stops 5 below; workday steppers still jump 15 min.

---

## §9 Non-goals & accepted trade-offs

**Non-goals:**

- **No new settings.** The skip countdown reuses `autoStartCountdownSeconds`; the four visible
  settings stay four.
- **No auto-start after a *completed* break.** That remains the unlock countdown's job, gated on
  proof of presence. Change 2 explicitly stops short of it.
- **No screen-share detection.** Not achievable on macOS today (§6.1); the live-call proxy is the
  whole mechanism.
- **No third countdown exit** ("start in 5 min", snooze) and no click-to-confirm on the HUD.
- **No log-schema change.** An auto-started session is indistinguishable from a manual one by
  design; re-entry latency stays derivable from existing timestamps.
- **No auto-close behaviour for a window the user opened**, by any timer or focus rule.

**Accepted trade-offs:**

- A skip cancelled at second 14 costs the user 14 seconds of nothing. The alternative — starting
  instantly — removes the escape hatch for a hold that completed by accident (a leaning wrist, a
  stuck trackpad), and that hold is 15 seconds of pressure, not a click.
- Change 5 over-suppresses by design: no HUD and no chime during calls where nothing is shared
  (§6.1).
- A break owed through a long call still expires unclaimed, and now does so with less on screen than
  before.
- Foregrounding at break end can pull the user out of a full-screen Space (§3.5).
- A Mac that never locks gets neither the unlock countdown nor the break-end foreground (§3.1).
- Abandoning now costs an extra window-open. Deliberate (§4.3).
- The `UnlockAutoStartService` → `AutoStartService` rename dirties a file the existing spec names by
  path; that spec gets a pointer rather than a rewrite.

---

## §10 Open questions for the implementing PR

1. **Idle menu-bar text** — under active discussion, not specced here: appending something like
   `Start 32m` to the status item when idle, potentially replacing the launch window and/or the
   break-end foreground (§3). It is the only surface in the app that satisfies principle 7
   unconditionally — a title change cannot land in a shared screen — so if it lands, §3 and §4.2
   should be revisited together rather than piecemeal. Needs: exact copy, click behaviour, and what
   it replaces.
2. **A call starting mid-break** leaves the overlay up (§6.5). Recommendation: leave it — the
   screen-lock makes it nearly unreachable, and tearing the overlay down would hand back a
   friction-free break skip. Revisit only if it happens in practice.
3. **Notifications during a call** stay on (§6.2). Recommendation: leave them — macOS Focus modes
   already own this, and the deferred-break banner is the only notice that a break is owed.

---

## §11 PURPOSE alignment

- **Serves the core loop (guide #1).** Changes 1 and 2 both act on the loop's return edge — the only
  transition still left to willpower. Change 1 covers the break you refused; change 2 covers the
  break you were present for; the unlock countdown already covered the break you walked away from.
  Together the three exhaust the ways a break can end with the user reachable.
- **Friction in the right places (principle 4), stated honestly.** Change 1 can be read as rewarding
  a skip. The counter is that it changes nothing about the skip's *price* — still 15 seconds of
  hold, still the nudge line, still logged as skipped — and changes only what follows: work, rather
  than a free-floating idle state the skip was never asking for. Nothing here makes skipping a break
  cheaper, which is the test guide #2 actually sets. Change 5 is checked against the same guide in
  §6.5: silence must not become a cheap exit from a break.
- **Surface area (principle 5).** Net: one new enum, one small monitor service, one rename, three
  effect cases, one menu item — and one *fewer* persistent window, plus three fewer things that can
  appear uninvited. Change 3 is a subtraction, and change 5 is a larger one.
- **Never interrupt a meeting (principle 7).** Written by this spec, and the reason changes 1–3 each
  carry a call gate rather than a "we'll see" note.
- **Local, private, native (principle 6).** No new permissions, no polling, no network. The lock
  signal is the same pair of distributed notifications already in use, now observed once instead of
  once per consumer; the call signal is the CoreAudio probe already shipping.
- **Not configurable infinitely.** Change 4 refines an existing dial rather than adding one; the
  personalisation surface is still exactly four settings.

---

## §12 Decision log

Recorded because §1 reconstructs *why*, not *who decided*. All answered by the owner before this
spec was written.

| Question | Decision |
|---|---|
| How should the next session begin after a completed skip hold? | 15-second cancellable countdown (not immediate, not a prompt). |
| What is on screen behind the skip countdown? | The overlay fades at once; the HUD floats over the desktop. |
| What is on screen after the skip auto-start fires? | Nothing — menu bar only. |
| Does cancelling the skip countdown also suppress the unlock countdown for that break end? | Yes. |
| Does the 30-minute call-cap skip also auto-start? | No — hold-to-skip only. |
| Should the HUD copy differ between the skip and unlock triggers? | No — one card to recognise. |
| What comes forward when a break ends unlocked? | The main window, activated, on the idle screen. |
| Does that foregrounding consume the unlock countdown's offer for that break end? | No — the unlock countdown is unchanged. |
| What if lock state was never observed? | Do nothing. Observed unlock only. |
| How is a session abandoned once there is no window? | Open the window from the menu bar; no new menu item for it. |
| When does a window opened mid-session close? | Only when the user closes it. |
| Does the app still open a window at launch? | Yes. |
| What else changes in Settings? | Nothing — the focus steppers only; workday steps and the 5-minute min/max gap stay. |
| Which countdown cancels open the main window? | Both — skip and unlock. |
| What signal suppresses the app during meetings? | Any live call (mic in use); screen-share detection isn't possible on macOS. |
| Does the window still come forward when a break is deferred by a call? | No — reversed. "Start break now" moves to the menu bar. |
| What happens when a call suppresses a countdown? | Nothing starts; the app goes idle. |
| How far does the principle reach? | Windows **and** sounds. Notifications stay. |
