# Feature spec — Unlock auto-start countdown

**Status:** Proposed · not yet implemented
**Scope:** One new service, one new HUD view, one pure gate, one log query, two hidden tunables, one status-item hook.

---

## §1 Why this exists

The loop's weakest joint is re-entry. The app already makes taking a break nearly unavoidable
(full-screen overlay, hold-to-skip, screen lock 30s in — PURPOSE principle 4), but once a break
completes with the user away from the machine, the app goes `.idle` and waits. Coming back from a
good break lands on a locked screen, then a desktop, then an inbox — and the next session starts
whenever willpower remembers to click "Start focus." Usage data says the loop works *when used*
(89% focus completion, 94% break completion); the gap this feature closes is the unmeasured minutes
between "back at the desk" and "next session running."

The mechanism exploits a guarantee the app itself created: because
[`ScreenLockService`](Sources/DynamicPomodoro/Services/ScreenLockService.swift) locks the screen 30
seconds into every break, any break the user physically walked away for ends with the screen locked.
The next unlock is therefore a high-precision "user just returned from a break" signal — no camera,
no idle timers, no permissions.

On that signal, the app offers to start the next focus session — **opt-out, not opt-in**. A small
floating countdown appears; doing nothing starts the session; one keypress cancels it. The tool
absorbs the restart decision the same way it absorbs the take-a-break decision (principle 4), while
keeping cancellation cheaper than the session it would start.

## §2 Trigger

Listen for the distributed notification the login window posts on every unlock:

- Center: `DistributedNotificationCenter.default()`
- Name: `com.apple.screenIsUnlocked` (and its sibling `com.apple.screenIsLocked`, see §5.4)
- Registered on the main queue; handling hops to `@MainActor`, matching the observer idiom in
  `TimerEngine` and `BreakOverlayManager`.

These names are undocumented but stable across macOS versions, and require no entitlement or TCC
prompt. That is in-house style already: `ScreenLockService` calls the private
`SACLockScreenImmediate` symbol for the same lock/unlock cycle this feature listens to.
Implementation should verify once, manually, that the `SACLockScreenImmediate` lock path emits the
pair on the target macOS version (it locks to the login window, so it should).

The notification fires on *every* unlock, so the trigger is deliberately dumb and all intelligence
lives in the gate (§3).

## §3 Gate

On each unlock, offer the countdown iff **all** of the following hold. The decision is a pure
function (`Logic/UnlockGate.swift`, §7) so every clause is unit-testable with synthetic dates.

| # | Condition | Rationale |
|---|-----------|-----------|
| G1 | `TimerEngine.state.phase == .idle` | Never interfere with a running focus, a pending break, or a running break (unlocking mid-break just resumes the overlay). |
| G2 | `SessionLogStore.lastBreakEnd()` is non-nil (§6) | The latest log entry is a break end — i.e. the loop paused at a break boundary and nothing has run since. |
| G3 | `now − lastBreakEnd` is within the staleness window (default 20 min, §8) | Returning hours later is a new day-part, not a continuation; a stale auto-start would be a jump-scare. Negative deltas (clock skew) also fail. |
| G4 | `lastBreakEnd != suppressedBreakEnd` (§5.3) | One offer per break end. A cancelled offer is not re-made on later unlocks in the same window. |
| G5 | No countdown is already active | Unlock notifications can arrive in duplicate bursts; the offer is idempotent. (Service-level guard, not part of the pure gate.) |

Both `breakCompleted` and `breakSkipped` count as a break end: each marks the boundary where a
focus→break cycle concluded, and the window (G3) plus one-keypress cancel bound the cost of offering
after a skip. Deliberate mid-focus abandons do *not* re-arm the offer — after `focusAbandoned` is
logged, G2 fails.

Call state is deliberately **not** a gate input: focus sessions may start during calls today (only
break *starts* defer), and the countdown changes nothing about that.

## §4 Countdown behaviour

On a passing gate:

1. A floating HUD (§5.1) appears on the display containing the cursor, counting down from
   `autoStartCountdownSeconds` (default 15, §8).
2. **Left alone** → when the countdown reaches zero, call `TimerEngine.startFocus()` — the *same
   method* the Idle screen button and the status menu's "Start focus" invoke. Identical duration
   curve, identical logging, identical "Focus started" notification. The trigger is different;
   nothing downstream is.
3. **Cancelled** → the HUD dismisses immediately, `suppressedBreakEnd` is set to the break-end
   being offered (G4), and no offer recurs for this break end. The next *completed cycle* produces a
   new break-end date, which naturally re-arms the feature — suppression never needs explicit reset.

The countdown is deadline-based (`Date` captured at show + N seconds), not tick-counted. On firing,
a guard checks wall-clock overshoot: if the deadline was missed by more than ~3 seconds (machine
slept mid-countdown, run loop stalled), dismiss silently instead of starting — the same
philosophy as `PomodoroReducer.missedDeadlineGraceSeconds`: never start a session on behalf of
someone who provably wasn't there for the decision.

### §4.1 Cancel paths (exactly two)

- **Esc**, captured *locally* by the HUD panel. The panel is key-able (`canBecomeKey` override, as
  `BreakOverlayManager.KeyablePanel` does) and made key on show, so Esc arrives through the normal
  responder chain (`cancelOperation(_:)` / `keyDown` keyCode 53). Deliberately **no global event
  monitor**: `addGlobalMonitorForEvents` would drag in an Input Monitoring / Accessibility prompt,
  violating the no-permissions posture (principle 6) for a 15-second convenience.
- **Click on the menu-bar status item**, short-circuiting its normal menu (§5.2).

Any other key pressed while the HUD is up is swallowed and ignored — it neither cancels nor
confirms. Consequence, accepted: for at most the countdown duration, keyboard focus rests on the
HUD, so a user who unlocks and instantly types loses those keystrokes. The HUD is on-screen,
counting, and names both exits; the alternative (any-key-cancels) would quietly cancel for exactly
the user who most needs a session running — the one already typing into work with no timer going.
The one-line reminder on the HUD (§5.1) exists so neither cancel path needs memorising.

### §4.2 Lock during countdown

If `com.apple.screenIsLocked` arrives while the countdown runs (user unlocked, saw the HUD, locked
again and left), dismiss silently **without** setting suppression — the user never said no, so a
later unlock inside the window offers again. This also prevents the worst outcome: a session
auto-starting into a locked, empty room.

## §5 HUD design & mechanics

### §5.1 Appearance

- Borderless `NSPanel`, style `[.borderless, .nonactivatingPanel]` — the Spotlight pattern: the
  panel can become key (for Esc) **without activating the app**. `NSApp.activate` is never called;
  the frontmost app keeps its frontmost status and the HUD stays an overlay, not an interruption.
- `level = .floating`; `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  so it appears even when the user unlocks into a full-screen Space.
- `animationBehavior = .none` — same macOS 26 lesson as `BreakOverlayManager`: implicit panel
  animations can wedge a borderless panel at its initial state. All animation is ours.
- Translucent, blurred, rounded card (`NSVisualEffectView` `.hudWindow` material, or SwiftUI
  `.ultraThinMaterial` — implementer's choice), clear panel background, standard shadow.
- Position: horizontally centered on the screen containing the cursor (reuse/extract the
  `currentScreen()` cursor logic from `BreakOverlayManager`), vertically in the top fifth of the
  visible frame — present without covering the middle of the desktop the user just returned to.
- Content, top to bottom:
  - Circular progress ring, ~96 pt, **draining** as time runs out (reuse
    [`TimerRing`](Sources/DynamicPomodoro/Views/FocusView.swift) if its size/stroke parameterise
    cleanly; otherwise a small local ring in the same visual language), with the integer seconds
    remaining centered in it, monospaced digits.
  - Title line: `Focus starts in 12s` (live).
  - Reminder line, secondary style: `Esc or click the menu bar icon to cancel` — one line, both
    cancel methods, nothing to memorise.
- Transitions: fade+scale in (~0.25 s ease-out, alpha 0→1 with a subtle SwiftUI scale 0.96→1),
  fade out (~0.2 s) on every exit path — cancel, lock-dismiss, overshoot-dismiss, and auto-start
  alike. Panel alpha animates via `NSAnimationContext`, matching the overlay manager idiom.

### §5.2 Status-item short-circuit

Today `setupStatusItem()` assigns `statusItem.menu`, so clicks open the menu and no button action
ever fires. While a countdown is active:

- Detach the menu (`statusItem.menu = nil`) and point `button.target`/`button.action` at a
  cancel selector.
- A click then cancels the countdown (with suppression, §4.1) and does nothing else — the menu does
  **not** open on that same click.
- When the countdown ends by any path, restore `statusItem.menu`. This requires keeping the menu in
  a property rather than a local (small refactor in `main.swift`).

The status item's icon and title are left unchanged during the countdown; the HUD is the countdown's
one visual surface.

### §5.3 Suppression state

`suppressedBreakEnd: Date?`, held in memory by the service, compared by equality against the log's
`lastBreakEnd()`. Not persisted: an app relaunch inside the 20-minute window may re-offer once after
a cancel, which costs one Esc and keeps the state surface at zero files. (§10 lists persisting it as
a rejected-for-now option.)

### §5.4 Focus-loss and edge interactions

- Clicking into another app's window mid-countdown takes key status from the panel (nonactivating
  panels don't fight for it). The countdown keeps running — the user is present and engaging with
  work, which is exactly when a session should start — but Esc no longer reaches the HUD; the
  status-item click remains. Accepted.
- The HUD card itself is not interactive; clicks on it do nothing (§10 revisits).
- Machine sleeps mid-countdown without locking → overshoot guard dismisses on wake (§4).
- If the user's lock settings never require a password (or they only ever display-sleep without
  locking), `com.apple.screenIsUnlocked` never fires and the feature is simply inert. Accepted: the
  feature keys off the lock the app itself causes 30 s into each break.

## §6 Session-log query

`SessionLogStore` gains one read helper beside its existing ones:

```swift
/// The moment the most recent break ended (completed or skipped), provided
/// nothing has run since. Focus sessions are logged when they *end*, and the
/// running case is excluded by the caller's phase gate (G1), so "the latest
/// entry is a break end" is exactly "no focus started after it".
func lastBreakEnd() -> Date? {
    guard let last = entries.last,
          last.kind == .breakCompleted || last.kind == .breakSkipped
    else { return nil }
    return last.endedAt
}
```

That comment carries the load-bearing subtlety: the log's append-only, chronological, logged-at-end
shape makes "last entry" sufficient, but only in combination with G1.

One consequence to name: a break that expires *during machine sleep* is completed by the wake-tick
with `endedAt ≈ wake time`, so the subsequent unlock sees a fresh break end and offers the
countdown even though the break's deadline passed hours ago in wall time. This is intended — the
unlock itself proves the user is present, the wake-tick already logged the break honestly, and the
worst case is one Esc.

## §7 Architecture & file map

Follows the repo's split — pure decisions in `Logic/`, effectful glue in `Services/`, SwiftUI in
`Views/`:

| File | Change |
|------|--------|
| `Logic/UnlockGate.swift` | **New.** Pure gate: `shouldOffer(phase:lastBreakEnd:suppressedBreakEnd:now:window:) -> Bool` (G1–G4) and `shouldStillFire(deadline:now:) -> Bool` (the ~3 s overshoot guard). No AppKit, no singletons. |
| `Services/UnlockAutoStartService.swift` | **New.** `@MainActor` service owning: both `DistributedNotificationCenter` observers, the countdown deadline + timer (scheduled in `.common` mode, as `TimerEngine`'s ticker is), `suppressedBreakEnd`, the HUD panel lifecycle, and `@Published private(set) var isCountingDown` + `func cancelCountdown(suppress: Bool)` for the status-item hook. Injected with `TimerEngine`, `Settings`, `SessionLogStore` — no new singletons. |
| `Views/CountdownHUDView.swift` | **New.** SwiftUI card per §5.1: ring, seconds, title, reminder line. Dumb view driven by the service. |
| `Models/SessionLog.swift` | Add `lastBreakEnd()` (§6). |
| `Models/Settings.swift` | Add the two tunables (§8), UserDefaults-backed and clamped like the existing four. |
| `main.swift` | Instantiate the service in `applicationDidFinishLaunching`; hold the status menu in a property; sink `isCountingDown` to swap menu ↔ cancel action (§5.2). `#if DEBUG`: a "Simulate unlock (test)" menu item (sibling of the fast-forward item) that invokes the same handler as a real unlock, so the HUD is exercisable without locking the machine. |
| `Tests/DynamicPomodoroTests/UnlockGateTests.swift` | **New.** See §9. |
| `Tests/DynamicPomodoroTests/SessionLogStoreTests.swift` | Extend for `lastBreakEnd()`. |
| `README.md` | In the implementing PR: architecture tree entries + one "Spec implementation notes" bullet. |

The panel subclass (key-able, `cancelOperation` → cancel) lives with the service or the view file;
`BreakOverlayManager.KeyablePanel` is private and stays that way.

## §8 Tunables

Two values, both persisted in `UserDefaults` through `Settings` (clamped on load, same pattern as
the existing four), **neither shown in `SettingsView`**:

| Property / key | Default | Clamp | Meaning |
|---|---|---|---|
| `autoStartCountdownSeconds` | 15 | 3…120 | HUD countdown length. |
| `autoStartWindowMinutes` | 20 | 1…180 | Staleness window for G3. |

Rationale for hiding them: PURPOSE principle 5 and "What this is not" promise a four-setting
personalisation surface, and the precedent for opinionated timings (`breakLockDelaySeconds`,
`missedDeadlineGraceSeconds`, `breakPendingCapSeconds`) is constants, not UI. Backing these two by
`UserDefaults` splits the difference: tunable without a rebuild (`defaults write` — this is a
personal tool), invisible in the UI, and the Settings window's promise stays intact. `Settings.swift`'s
"four values" header comment gets updated to say so honestly.

## §9 Testing

**Unit (swift-testing, synthetic dates — no timers, no AppKit):**

- `UnlockGateTests`: each gate clause independently — non-idle phases (G1); nil break end (G2);
  inside/outside/exactly-at window, negative delta (G3); suppressed vs different break end (G4);
  `shouldStillFire` at/over the overshoot grace.
- `SessionLogStoreTests`: `lastBreakEnd()` on an empty log; last entry `focusCompleted` /
  `focusAbandoned` → nil; last entry `breakCompleted` / `breakSkipped` → its `endedAt`; break
  followed by a later focus entry → nil.

**Manual checklist (real machine, DEBUG build):**

1. "Simulate unlock (test)" while idle with a fresh break end → HUD appears on the cursor's
   display; ring drains; at zero a normal focus session starts ("Focus started" notification, curve
   duration, log entry — all identical to a button start).
2. Esc mid-countdown → fades out; simulate unlock again → no re-offer (suppressed). Complete a full
   cycle → offer returns.
3. Status-item click mid-countdown → cancels, menu does not open; after countdown, click opens the
   menu as before.
4. Real flow: start focus → break → walk away past the 30 s lock → let break finish → return,
   unlock → HUD. Unlock *during* the break instead → no HUD, overlay resumes.
5. Unlock into a full-screen Space → HUD visible there.
6. Lock again mid-countdown, unlock → offered again (no suppression from lock-dismiss).
7. Sleep the machine mid-countdown, wake past deadline → no session started, HUD gone.

## §10 Non-goals, accepted trade-offs, open questions

**Non-goals (this iteration):**

- **Unlock-and-walk-away-again**: the session can auto-start with nobody there. Accepted cost of
  the opt-out design; the overshoot guard (§4) removes the mechanical variant (sleep), not the
  human one. If dogfooding shows phantom sessions, that's a *separate* idle-detection feature — not
  patched into this one.
- No idle/inactivity detection during a running session, same reasoning.
- No snooze / "start in 5 min" third option — two exits (start, cancel) keep the HUD one glance.
- No new `SessionLogEntry` field for trigger provenance — auto-start is *identical* to manual by
  design. Re-entry latency (break `endedAt` → next focus `startedAt`) is already derivable from the
  existing schema, and that delta shrinking is the feature's success metric for the §10-style
  review. Cancel *rate* is not measurable without new logging; deferred until the metric is missed.

**Accepted trade-offs:** keyboard focus rests on the HUD for ≤ the countdown (§4.1); in-memory
suppression may re-offer once after a relaunch (§5.3); wake-completed stale breaks still trigger an
offer (§6); undocumented notification names (§2).

**Open questions for the implementing PR:**

1. Should the two tunables ever surface in `SettingsView`? Recommendation: no, per §8.
2. Click-on-HUD as a third cancel path? Recommendation: no — two deliberate paths, and a stray
   click on a just-unlocked desktop shouldn't silently eat the offer. Revisit if Esc discovery
   fails in practice.
3. Persist `suppressedBreakEnd` (e.g. a UserDefaults date)? Recommendation: no until a relaunch
   re-offer actually annoys in practice.

## §11 PURPOSE alignment

- **Serves the core loop (guide #1):** focus → break → *focus* — this closes the loop's return
  edge, the only unassisted transition left.
- **Friction in the right places (principle 4):** skipping a break stays expensive; resuming work
  becomes free. Both directions of asymmetry point the same way: toward the loop continuing.
- **Surface area (principle 5):** zero new windows, zero new Settings UI, one transient HUD, two
  hidden tunables. The feature is invisible until the exact moment it's useful, and one keypress
  makes it gone.
- **Local, private, native (principle 6):** one distributed-notification observer; no permissions,
  no polling, no network, nothing persisted beyond two defaults keys.
