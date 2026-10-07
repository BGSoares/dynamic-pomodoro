# Feature spec — Loop continuity, window discipline, meeting silence

**Status:** Proposed. Every experience decision below was settled with the owner (§13 records
them); §11 lists what is still open.
**Scope:** six changes. Two close the loop's return edge, three move the app off the screen and
into the menu bar, one refines a dial.

| # | Change | One line |
|---|--------|----------|
| 1 | **Skip auto-start** | Completing the 15-second skip hold starts a 15-second cancellable countdown into the next focus session. |
| 2 | **Break-end foreground** | A break that ends while the screen is *known unlocked* brings the app forward on the idle screen — and deliberately does **not** auto-start anything. |
| 3 | **Window discipline** | The main window exists to take a decision. No window at launch, none during a focus session; the menu bar is the timer. |
| 4 | **Idle menu-bar action** | While idle the status item reads `Start 32m` — live from the curve — and one click starts that session. |
| 5 | **Meeting silence** | While a call is live the app shows nothing and plays nothing. New PURPOSE principle 7; cuts across 1–4. |
| 6 | **1-minute steps** | The two focus-duration steppers in Settings move a minute at a time instead of five. |

Changes 1 and 2 reuse the unlock countdown's machinery;
[`SPEC_UNLOCK_AUTOSTART.md`](SPEC_UNLOCK_AUTOSTART.md) stays authoritative for the unlock trigger,
with one amendment forced by change 5 (§6.5).

---

## §1 Why

**Change 1 — the skip is a decision to keep working, and the app currently ignores it.** Holding
the skip button for 15 seconds is the most deliberate act in the app. What follows it today is
`.idle`: the overlay fades, nothing runs, and the next session starts whenever willpower remembers
the menu bar. The person who just paid 15 seconds to *not* stop is exactly the person who wanted to
be in a session immediately.

**Change 2 — the app is invisible at the one moment it has something to say.** Breaks usually end
with the screen locked, which is what the unlock countdown is built on. The unhandled case is the
break that runs out with the machine awake and unlocked: the overlay fades and reveals the desktop,
and nothing marks the transition. It must not auto-start, and the reason is specific — an unlock is
*proof of presence* (someone typed a password), which is what licenses the unlock countdown to act
opt-out. A break ending proves nothing; the user may have unlocked, glanced at the overlay, and
walked away. So this surfaces a choice and never makes one.

**Change 3 — the window outlived its job.** The window is where you start a session and where you
abandon one. Between those moments it shows a ring the menu bar already shows, sitting in ⌘-Tab and
in the way.

**Change 4 — the menu bar can carry the whole idle state.** `IdleView` shows two things: what the
curve is offering right now, and a button. Both fit in a status item — `Start 32m` says the number
and invites the click. This is what makes change 3 safe rather than merely smaller: the affordance
it removes from the screen reappears somewhere that costs nothing.

**Change 5 — a shared screen makes every surface a liability.** A full-screen "TAKE A BREAK" card
landing in someone else's meeting window is the worst thing this tool could do. The app already
holds breaks back during calls; principle 7 generalises that to every window, panel, and chime.

**Change 6 — 5-minute granularity is coarser than the curve.**
[`DurationCurve`](Sources/DynamicPomodoro/Logic/DurationCurve.swift) interpolates and rounds to the
minute, so 27- and 33-minute sessions already happen. Only the *bounds* were stuck on multiples of
five, which is an arbitrary limit on the one dial the tool respects.

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
appearing over that call, on its way to starting a session nobody asked for, is a jump-scare — and
after change 5 it would be suppressed anyway. That path keeps today's behaviour exactly: go idle,
log it, say nothing.

The two paths are already separate reducer branches, so the distinction is a matter of which branch
emits the new effect — and is directly unit-testable (§9).

### §2.3 Countdown behaviour

On a completed hold:

1. The break overlay begins its normal 1.5 s fade-out immediately (the existing `.breakRunning →
   .idle` phase sink in `main.swift` — untouched).
2. The countdown HUD from [`SPEC_UNLOCK_AUTOSTART.md §5`](SPEC_UNLOCK_AUTOSTART.md) appears over the
   revealed desktop: same panel, same card, same copy, same ring, same position, counting down from
   `autoStartCountdownSeconds` (default 15).
3. **Left alone** → `TimerEngine.startFocus()`, identical in every respect to a button start. Per
   change 3 no window appears; the menu-bar timer is the only sign.
4. **Cancelled** (Esc, or a click on the menu-bar item) → the HUD dismisses, the skip stands, the
   app goes idle **and the main window opens** (§4.2) so the cancel lands somewhere rather than
   nowhere. That presentation is itself call-gated (§6.2).
5. **A call is live at step 2** → none of this happens. No HUD, no session, no window; the app goes
   idle exactly as it does today (§6.3).

Deadline-based timing and the ~3 s overshoot guard (`UnlockGate.shouldStillFire`) apply unchanged:
if the machine sleeps mid-countdown, nothing starts on wake.

### §2.4 Cancel suppression, and why the effect order matters

`AutoStartService` already records `offeredBreakEnd` when a countdown starts and, on a suppressing
cancel, writes it to `suppressedBreakEnd` — which gate clause G4 checks on every subsequent unlock.
Feeding the skip countdown through the same field gives the decided behaviour for free: cancelling
the skip countdown means locking and unlocking ten minutes later will *not* re-offer for that break.

This depends on the skip's log entry being written **before** the countdown is offered, since
`offeredBreakEnd` is read from `SessionLogStore.lastBreakEnd()`. Effects are interpreted in array
order, so the `.skipBreak` case must return `.logSession` ahead of the offer effect. A test pins the
order (§9) — it is load-bearing, not cosmetic.

### §2.5 Edge cases

- **Lock during the countdown** — dismiss, no suppression (existing `handleLock`): the user never
  said no, and a later unlock inside the 20-minute window may still legitimately offer. Also rules
  out a session auto-starting into a locked, empty room.
- **A countdown already running** — impossible in practice (a break was running a moment ago, so the
  unlock gate's G1 could not have fired), but `guard !isCountingDown` covers it.
- **Quit during the countdown** — allowed. `applicationShouldTerminate` blocks only `.breakRunning`
  / `.breakPending`; the phase here is `.idle`.
- **The skipped break's activity** is logged as today. Nothing about the bookkeeping changes.

---

## §3 Change 2 — Break-end foreground

### §3.1 Knowing whether the screen is unlocked

The app already observes `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` inside
`UnlockAutoStartService`. Change 2 needs that as *state* rather than as events, and change 1 leaves
two consumers, so the observation moves into one place:

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
next unlock.

### §3.2 Gate

At break completion, foreground iff **all** of:

| # | Condition | Rationale |
|---|-----------|-----------|
| F1 | The break ended by **completing** (`completeBreak`), not by a skip or the call cap | A skipped break is change 1's business; the call-cap break is nobody's (§2.2). |
| F2 | `ScreenLockState == .unlocked` | The whole point: the screen is awake and someone unlocked it. `.locked` belongs to the unlock countdown; `.unknown` is not evidence (§3.1). |
| F3 | No live call | Principle 7 (§6). A break can only be running during a call if the call started mid-break, but that is exactly the case that matters. |

No time window and no suppression: the trigger is a single instantaneous transition, so neither can
apply.

### §3.3 What comes forward

The existing main window, activated, on the idle screen — `openMainWindow()`, which already ends in
`NSApp.activate(ignoringOtherApps:)`. `MainWindowView` routes on phase and the phase is `.idle` by
then, so the content is `IdleView`: *"Ready / Next session: 32 min"*, the daily stats footer, and a
**Start focus** button already wired to `.keyboardShortcut(.return)`. One keypress starts the
session; doing nothing starts nothing.

No new view, no new window, no countdown, no auto-start.

The break-complete chime and the "Break complete — Ready when you are" notification are unchanged,
full stop — neither is gated on anything (§6.4).

**Ordering note for the implementer:** the overlay's fade-out (1.5 s, shielding level) is still
running when the window is presented, so the window is revealed *by* the fade rather than popping
over it — the nicer transition, and the reason to present immediately rather than waiting for the
fade to finish. Worth confirming by eye (§9) that the main window ends up key once the shielding
panels order out.

### §3.4 Relationship with the unlock countdown — deliberately none

If the user is fronted the window, walks away, the Mac locks itself, and they return and unlock
inside the 20-minute window, the unlock countdown offers and auto-starts as it does today. The later
unlock is fresh proof of presence, and nothing about the earlier foregrounding contradicts it. The
foreground path writes nothing to `suppressedBreakEnd`.

### §3.5 Edge cases

- **User is in another app's full-screen Space** — activation may switch Spaces. Accepted: the break
  overlay covered that Space thirty seconds ago; this is less disruptive than what preceded it.
- **Break completed by the wake-tick after sleep** — the machine woke, so a lock/unlock pair almost
  certainly preceded it; if the state says unlocked, the user is there and the window is correct.

---

## §4 Change 3 — Window discipline

### §4.1 The rule

> The app never puts a window on screen unless it needs a decision it cannot ask for in the menu
> bar — and never while a call is live. Everything else lives in the status item.

After changes 3 and 4 the app opens a window on its own in exactly **two** situations: a break
ending while unlocked (§3), and the cancellation of a countdown (§2.3, §4.2). Launch is no longer
one of them.

### §4.2 Per-phase behaviour

| Moment | Window | Why |
|---|---|---|
| **Launch** | **None** (changed) | The status item says `Start 32m` and one click starts it (§5). A window at launch would be showing you a button you already have. |
| Focus starts — *any* path: menu-bar click, menu item, skip countdown, unlock countdown | **Hides** (`orderOut`) | The menu-bar `F 24:59` is the whole UI for a running session. |
| During any phase, user picks **Open** from the menu | **Opens** | Explicit user request. Never suppressed, not even during a call (§6.2). |
| A window the user opened | **Stays until they close it** | No auto-close timers, no close-on-deactivate. |
| Focus ends, break starts | Overlay takes over; window untouched | `BreakMirrorView` still mirrors state if a window happens to be open. |
| Focus ends **on a call** → `.breakPending` | **None** (changed) | Principle 7. The "Start break now" override moves to the menu (§4.3). |
| Break completes, screen unlocked, no call | **Opens** | §3. |
| Break completes, screen locked | Nothing | Nobody is there; the unlock countdown handles the return. |
| Break skipped | Nothing | §2 starts a session instead, and a session means no window. |
| A countdown is cancelled | **Opens** (unless a call is live) | The cancel is a decision to *not* start now; the idle screen is where the next one is taken. Applies to both the skip and unlock countdowns. |

The behavioural removals in `main.swift`: `applicationDidFinishLaunching` no longer calls
`openMainWindow()`, and `menuStartFocus()` no longer does either.

### §4.3 One new menu item, and it isn't abandon

`.breakPending` used to be reachable only through the main window, which is where "Start break now"
lives — and principle 7 forbids that window at exactly the moment it would appear. So the status
menu gains **"Start break now"**, hidden unless the phase is `.breakPending`, calling
`timer.startPendingBreak()`. Shown/hidden from the existing phase sink; no new state.

Abandon does **not** get the same treatment. Abandoning is menu bar → **Open** → **Abandon session**
→ confirm: four interactions guarding a destructive, irreversible discard, keeping abandon more
expensive than start, in the same place it has always been (PURPOSE principle 4).

### §4.4 Nothing else moves

`MainWindowView`'s routing, `MainWindowDelegate`'s hide-instead-of-destroy behaviour, the Settings
window, and the rest of the status menu are unchanged.

---

## §5 Change 4 — Idle menu-bar call to action

### §5.1 The title

`updateStatusItemTitle(for:)` already writes `button.attributedTitle` per phase in the app's
monospaced-digit menu-bar font; the `.idle` case is `""` today. It becomes:

| Phase | Title |
|---|---|
| `.idle` | `Start 32m` — the integer from `TimerEngine.suggestedFocusMinutes()` |
| `.focus` | `F 24:59` (unchanged) |
| `.breakPending` | `Calls over` (amended 2026-10-07: was `B …`, whose literal ellipsis read as a truncated title) |
| `.breakRunning` | `B 04:12` (unchanged) |

Roughly the width of the running-session title, so the status item does not visibly resize as the
loop turns.

### §5.2 Keeping the number honest

The suggestion is a function of *now*: `DurationCurve` moves the number continuously along the
cosine, the first-session-of-day rule flips after the first completed focus, and both reset at
midnight. But the title is currently driven by `timer.$state`, which **never emits while idle** — so
a naive implementation would freeze the number at whatever the curve said when the last break ended,
and quietly lie for the rest of the day.

Accuracy therefore needs a cadence. The implementation is a repeating 60-second `Timer` that exists
**only while the phase is idle** — created on entering idle, invalidated on leaving it — with a
generous `tolerance` (~15 s) so macOS coalesces the wakeups. Sixty seconds is exactly the precision
the title displays, so the number is never wrong by more than the unit it is written in, and the
"no idle wakeups" property `main.swift:50` claims for the *running* case is preserved where it
matters — during a session, the state stream still drives everything and the extra timer does not
exist.

Recompute additionally on: `Settings` changes (min/max/workday all move the curve),
`NSWorkspace.didWakeNotification`, and `NSApplication.didBecomeActiveNotification` — the same
staleness seams `IdleView` already covers for the same reason (`IdleView.swift:43`). Phase changes
already recompute, which covers the first-session-of-day flip.

### §5.3 Click behaviour

Today `statusItem.menu` is assigned, so clicks open the menu and `button.action` never fires. The
countdown feature already demonstrates the alternative — detach the menu, point `button.action` at a
selector (`main.swift:143`) — and this change generalises it. Precedence, highest first:

| State | Left click | Right / Control click |
|---|---|---|
| A countdown is running | **Cancels the countdown** (existing behaviour, §2.3) | Cancels the countdown |
| `.idle`, no countdown | **Starts the focus session** | Opens the menu |
| `.focus` / `.breakPending` / `.breakRunning` | Opens the menu | Opens the menu |

Implementation: while idle, `statusItem.menu = nil`, `button.target/action` set, and
`button.sendAction(on: [.leftMouseUp, .rightMouseUp])`; the action inspects `NSApp.currentEvent` for
button number and `.control` modifier, and for the menu case does the standard dance — reattach
`statusItem.menu`, `button.performClick(nil)`, detach again on `menuDidClose`. The countdown's
existing attach/detach must compose with this rather than fight it: one function owns the status
item's menu-vs-action mode and is called from both the phase sink and the countdown sink.

Accepted, per the decision: a stray menu-bar click while idle starts a session. Abandon is the
remedy, and the same click during a *running* session cannot start anything.

---

## §6 Change 5 — Meeting silence (PURPOSE principle 7)

### §6.1 The signal

`CallDetectionService.isOnCall()` — CoreAudio input-device state, no capture, no permission prompt.
Every meeting app holds the input stream open while a call is live, muted or not.

There is **no public macOS API that reports another app capturing or sharing your screen.** Apple's
Screen Sharing agent is detectable; Zoom, Meet, and Teams screen shares are not. A live call is
therefore the proxy — deliberately the broader signal, because being wrong in the other direction is
unrecoverable. The blind spot is written down here so a future macOS release can close it.

**Implementation note:** the `DP_FAKE_ON_CALL` DEBUG env override currently lives in
`TimerEngine.defaultCallProbe`. Move it into `CallDetectionService.isOnCall()` itself so every new
consumer honours it — otherwise half of §9's manual checklist is untestable.

### §6.2 What is suppressed while a call is live

| Surface | Behaviour |
|---|---|
| Break-end foreground (§3) | Not presented (F3). |
| Countdown-cancel window (§4.2) | Not presented. |
| Countdown HUD, both triggers (§2, unlock) | Not shown, and no session starts (§6.3). |
| `.breakPending` window | Already removed by §4.3 — the menu item replaces it. |
| Full-screen break overlay | Structurally impossible already — see §6.4. No code. |
| Chimes | Nothing to gate — see §6.4. No code. |

**Not suppressed:** the menu-bar title and its click behaviour (ambient, cannot land in a shared
screen); user notifications (macOS Focus modes are the right layer, and the "break starts when your
call ends" banner is the only signal that a break is owed); a window the user opens themselves from
the menu; and **anything downstream of "Start break now"** (§4.3) — that override exists precisely
for a false call signal, so the break it starts runs in full, overlay and chime included.

The rule underneath all of this: the app never puts a window on screen, or a sound in the room,
*that the user did not ask for*, while a call is live. Esc-to-cancel is a request to stop a
countdown, not a request for a window. "Start break now" is a request for a break.

### §6.3 A suppressed countdown starts nothing

When a call suppresses the HUD, the app goes idle and stays there. It does **not** start the session
silently, even though a running session has no window and would disturb nothing visually: nothing in
this app begins without the user having seen the countdown that offered it. The offer is dropped
rather than queued, and no suppression flag is written — so a later unlock inside the window can
still offer once the call is over.

### §6.4 Why the overlay and the chimes need no code

A call cannot begin during a break. The overlay covers every display at shielding level and the
screen locks 30 seconds in, so joining a meeting requires getting past both — which means holding
skip for 15 seconds, which *ends the break*. And a break never starts during a call in the first
place (`.breakPending`). The two states are mutually exclusive by construction, not by a check.

That leaves exactly two ways `isOnCall()` can read true while a break runs, and neither wants
suppressing:

- **The explicit override.** "Start break now" (§4.3) deliberately starts a break while the probe
  says a call is live — it is the escape valve for a false positive, or a call the mic outlives.
  Suppressing its overlay would break the one control that exists to overrule the probe, and
  suppressing its chime would silence a break the user asked for out loud.
- **A lingering mic stream.** A meeting app that holds the input device open after a call, or an
  always-on audio tool. No real call, nobody to disturb; `breakPendingCapSeconds` already exists
  because the codebase knows this happens.

So principle 7's sound clause is satisfied structurally: every chime path either cannot coincide
with a live call, or is one the user requested. Gating `SoundService` would be dead code that only
ever fired on a false positive. The principle still governs anything added later — it just costs
nothing today.

The window and HUD suppressions are **not** in this category and do real work: unlocking into a
live call is entirely ordinary (dialled in, muted, screen locked while you stepped away, break ends,
you come back), and that is exactly when a countdown card must not appear over a shared screen.

The one clause this reasoning leaves thin is F3 on the break-end foreground (§3.2), which can now
only fire when the probe is wrong — after an override, or on a stuck stream. It stays anyway: one
gate, applied uniformly, in one place. The cost is an occasional un-fronted window; the cost of the
opposite mistake is the reason principle 7 exists.

### §6.5 Amendment to SPEC_UNLOCK_AUTOSTART.md

That spec's §3 says: *"Call state is deliberately **not** a gate input."* Principle 7 reverses it.
The implementing PR amends that line and adds the call clause to the unlock service's entry point.
`UnlockGate`'s pure functions and their tests are unaffected — the call check sits in the service,
alongside the `isCountingDown` guard, because it is a live environment query rather than a decision
about dates.

---

## §7 Change 6 — 1-minute duration steps

In [`SettingsView`](Sources/DynamicPomodoro/Views/SettingsView.swift), on the two "Focus duration"
steppers only:

| | Before | After |
|---|---|---|
| Minimum stepper | `in: 5...60, step: 5` | `in: 5...60, step: 1` |
| Maximum stepper | `in: 10...90, step: 5` | `in: 10...90, step: 1` |
| Min/max separation guard (`max ≥ min + 5`) | 5 min | **5 min — unchanged** |
| Workday Start/End steppers | `step: 15` | **`step: 15` — unchanged** |

So 22/37 becomes settable; 38/40 still snaps to 35/40. The guard staying at five while the step
drops to one keeps the curve's span meaningfully wide without constraining where that span sits.

`Settings.init`'s clamps already express the same rule arithmetically and need no change — they
never assumed multiples of five.

---

## §8 Architecture & file map

Pure decisions in `Logic/`, effectful glue in `Services/`, AppKit wiring in `main.swift`.

| File | Change |
|------|--------|
| `Logic/ScreenLockState.swift` | **New.** The three-case enum (§3.1). Pure, no AppKit. |
| `Services/ScreenLockMonitor.swift` | **New.** `@MainActor`, owns the two `DistributedNotificationCenter` observers, publishes `state: ScreenLockState`, exposes an unlock hook. Absorbs the observer code currently inside `UnlockAutoStartService`. |
| `Services/UnlockAutoStartService.swift` → `Services/AutoStartService.swift` | **Renamed** (two triggers now). Loses its observers to the monitor; gains `offerAfterSkip(now:)` beside `handleUnlock(now:)`, both funnelling into the existing `startCountdown(now:breakEnd:)` and both returning early on a live call (§6.3). Cancel paths call the window presenter (§4.2). `CountdownHUDView`'s `@ObservedObject` type follows the rename. |
| `Services/CallDetectionService.swift` | Absorb the `DP_FAKE_ON_CALL` DEBUG override from `TimerEngine` (§6.1). |
| `Core/PomodoroCore.swift` | Three new `PomodoroEffect` cases: `.offerAutoStart` (from `.skipBreak`, **after** `.logSession`), `.presentMainWindow` (from `completeBreak` only), `.hideMainWindow` (from `.startFocus`). The `.breakPending` entry points and the cap branch emit none of them (§2.2, §4.3). |
| `Services/TimerEngine.swift` | Interprets the three effects by forwarding to injected closures (default no-ops, so tests stay AppKit-free). No chime gate (§6.4) and no lock probe — the lock check lives with the window presenter. |
| `main.swift` | Owns `ScreenLockMonitor` and the presenter `presentMainWindow(requireUnlocked:)`, which applies F2/F3 in one place: `requireUnlocked: true` from the break-end effect, `false` from a countdown cancel. Drops `openMainWindow()` from launch and from `menuStartFocus()`. Adds the phase-gated "Start break now" item (§4.3). Rewrites `updateStatusItemTitle` for the idle title, adds the idle-only 60 s ticker and its recompute seams (§5.2), and unifies the status item's menu-vs-action mode across the idle click and the countdown short-circuit (§5.3). |
| `Views/SettingsView.swift` | `step: 5` → `step: 1`, twice (§7). |
| `PURPOSE.md` | Principle 7 (**already added in this PR**). |
| `Tests/.../PomodoroCoreTests.swift` | Extended — the effect-emission matrix, §9. |
| `Tests/.../ScreenLockStateTests.swift` | **New.** Small; §9. |
| `SPEC_UNLOCK_AUTOSTART.md` | One-line amendment to §3 (§6.5) plus the rename pointer. |
| `README.md` | Architecture tree entries, and "Spec implementation notes" bullets. |

`UnlockGate`'s pure functions are untouched.

---

## §9 Testing

**Unit (swift-testing, synthetic dates, no timers, no AppKit):**

- `PomodoroCoreTests`, effect emission:
  - `.skipBreak` from `.breakRunning` emits `.offerAutoStart`, **positioned after** `.logSession`
    (assert array order, not membership — §2.4).
  - `.tick` past `breakPendingCapSeconds` logs `breakSkipped` and emits **no** `.offerAutoStart`
    (§2.2) — the most important negative test in this spec.
  - Break completing emits `.presentMainWindow`; `.startFocus` emits `.hideMainWindow`.
  - Entering `.breakPending` (tick path and fast-forward path) emits **no** window effect (§4.3).
  - `.startPendingBreak` while the call probe is true still emits `.playFocusCompleteChime` and
    enters `.breakRunning` — the override is exempt from principle 7 (§6.4), and a regression here
    would silently disable the escape valve.
- `ScreenLockStateTests`: `.unknown` and `.locked` do not satisfy F2; `.unlocked` does.
- Existing `UnlockGateTests` and `SessionLogStoreTests` must pass **unchanged** — proof the unlock
  countdown's date logic was not disturbed.

**Manual checklist (real machine, DEBUG build):**

1. Launch → **no window**; status item reads `Start 32m`. Left-click → session starts, title flips
   to `F …`, still no window. Right-click → menu.
2. Leave the app idle across a curve inflection (or move the workday settings) → the idle title
   tracks it within a minute; leave it idle for an hour and confirm no battery/wakeup regression.
3. Break running → hold skip to completion → overlay fades, HUD counts 15 → focus starts, no window.
4. Same, Esc mid-countdown → HUD goes, **window opens** on the idle screen. Lock and unlock inside
   20 min → **no** re-offer. Complete a full cycle → offers again.
5. Same, click the menu-bar item mid-countdown → cancels (does **not** start a session, does not
   open the menu); menu works again after.
6. Start focus → window disappears. Menu → Open → focus ring + Abandon; it never closes itself.
   Abandon → confirm → idle.
7. Break ends while unlocked → window forward on the idle screen, nothing auto-starts; Return starts
   and the window disappears. Stay locked through the end instead → no window; unlock → countdown.
8. Relaunch mid-break, let the break end while unlocked → no foregrounding (`.unknown`, §3.1).
9. `DP_FAKE_ON_CALL=1`: fast-forward a focus session → `.breakPending`, **no window**, "Start break
   now" appears in the menu. Click it → the break runs in full, overlay and chime, despite the
   "call" (§6.4). Simulate unlock while idle → **no HUD, no session**; clear the variable, simulate
   again → HUD returns.
10. Settings → focus steppers move 1 min at a time; drag the minimum up and confirm it stops 5 below
    the maximum; workday steppers still jump 15 min.

---

## §10 Non-goals & accepted trade-offs

**Non-goals:**

- **No new settings.** The skip countdown reuses `autoStartCountdownSeconds`; the four visible
  settings stay four.
- **No auto-start after a *completed* break.** That stays the unlock countdown's job, gated on proof
  of presence.
- **No screen-share detection.** Not available (§6.1); a live call is the proxy.
- **No third countdown exit** ("start in 5 min") and no click-to-confirm on the HUD.
- **No log-schema change.** An auto-started session is indistinguishable from a manual one by design.
- **No auto-close for a window the user opened**, by any timer or focus rule.
- **No abandon item in the menu bar** (§4.3).

**Accepted trade-offs:**

- A skip cancelled at second 14 costs 14 seconds of nothing. The alternative — starting instantly —
  removes the escape hatch for a hold completed by accident, and that hold is 15 seconds of
  pressure, not a click.
- A stray menu-bar click while idle starts a session (§5.3).
- The daily stats footer now only exists in a window the user opens deliberately (§4.2). The menu
  bar carries the duration, not the history.
- The idle title costs a coalesced wakeup a minute while idle (§5.2) and permanent menu-bar width.
- A Mac that never locks gets neither the unlock countdown nor the break-end foreground (§3.1).
- Long calls silently eat breaks and suppress offers (principle 7's stated price).
- F3 (§3.2) can now only fire when the call probe is wrong — after an override or on a stuck mic
  stream — costing an occasional un-fronted window. Kept for uniformity: one gate, one place (§6.4).
- The `UnlockAutoStartService` → `AutoStartService` rename dirties a file the existing spec names by
  path; that spec gets a pointer, not a rewrite.

---

## §11 Open questions for the implementing PR

None. The three raised in review are settled and folded in above: the idle title reads `Start 32m`;
the title stays visible during calls; and "a call starting mid-break" turned out not to be a
scenario at all, which is what §6.4 is now about.

One thing to watch rather than decide: the status item now carries three different click meanings
(cancel a countdown, start a session, open the menu) across four phases. That is the only place in
this spec where two features share a control, and §5.3's precedence table is the whole of the
contract — implement it as one function that owns the status item's mode, not as two features each
reaching for `statusItem.menu`.

---

## §12 PURPOSE alignment

- **Serves the core loop (guide #1).** Changes 1 and 2 act on the loop's return edge — the only
  transition left to willpower. Change 1 covers the break you refused, change 2 the break you were
  present for, and the existing unlock countdown the break you walked away from. Together they
  exhaust the ways a break can end with the user reachable.
- **Friction in the right places (principle 4), stated honestly.** Change 1 can be read as rewarding
  a skip. The counter: it changes nothing about the skip's *price* — still 15 seconds of hold, still
  the nudge line, still logged as skipped — and changes only what follows. Change 4 makes *starting*
  one click while abandoning stays four interactions, which points the asymmetry the same way.
- **Surface area (principle 5).** Net: one new enum, one small monitor, one rename, three effect
  cases, one menu item — against two windows removed (launch, deferred break) and a window that no
  longer exists during any session. The app's resting state is now a status item.
- **Local, private, native (principle 6).** No new permissions, no polling of anything external, no
  network. One coalesced timer while idle; the lock signal is the same notification pair, now
  observed once instead of once per consumer.
- **Never interrupt a meeting (principle 7).** Change 5 is the principle; changes 1–4 are written to
  obey it, and §6.2 lists every surface it touches.

---

## §13 Decision log

All answered by the owner before this spec was written.

| Question | Decision |
|---|---|
| How should the next session begin after a completed skip hold? | 15-second cancellable countdown. |
| What is on screen behind the skip countdown? | Overlay fades at once; HUD over the desktop. |
| What is on screen after the skip auto-start fires? | Nothing — menu bar only. |
| Does cancelling the skip countdown suppress the unlock countdown for that break end? | Yes. |
| Does the 30-minute call-cap skip also auto-start? | No — hold-to-skip only. |
| What comes forward when a break ends unlocked? | The main window, activated, on the idle screen. |
| Does that consume the unlock countdown's offer for that break end? | No — the unlock countdown is unchanged. |
| What if lock state was never observed? | Do nothing. Observed unlock only. |
| How is a session abandoned once there is no window? | Open the window from the menu bar; no new menu item for it. |
| When does a window opened mid-session close? | Only when the user closes it. |
| Does cancelling a countdown open the window? | Yes — both the skip and the unlock countdown. |
| What else changes in Settings? | Nothing — the focus steppers only. |
| How far does "never interrupt a meeting" reach? | Windows **and** sounds. Notifications stay. |
| What signals a meeting, given screen-sharing is undetectable? | Any live call (mic in use). |
| Deferred break: window or principle? | Principle — no window; "Start break now" moves to the menu bar. |
| What happens when a call suppresses a countdown? | Nothing — stay idle. No silent session start. |
| Idle menu-bar title? | `Start 32m`, live from the curve, always accurate. |
| What does clicking it do? | Starts the session immediately; right-click opens the menu. |
| Which windows does it replace? | The launch window. The break-end foreground stays. |
| Idle title copy: `Start 32m` or `Start 32`? | `Start 32m`. |
| Should the idle title be hidden during a call? | No — keep it. |
| Should the overlay be torn down if a call starts mid-break? | Moot — it cannot happen (§6.4). |
