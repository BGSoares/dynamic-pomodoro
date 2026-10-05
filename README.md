# Dynamic Pomodoro

macOS menu-bar pomodoro timer with session durations that follow a bell curve across the workday, plus active break prompts drawn from a curated activity library.

Built to a v0.2 product spec kept outside this repo. Native Swift / SwiftUI + AppKit.
Only runtime dependency is [Sparkle](https://sparkle-project.org) (auto-update).

## Build & run

```bash
swift run
```

The app launches into the menu bar (no Dock icon). Look for the timer icon in the upper-right of the screen. No onboarding — first launch lands on Idle with sensible defaults.

## Validation

Nothing ships unrehearsed (PURPOSE principle 9). The pure core — every decision the user can
see — also builds on Linux (same module name, same tests; `Package.swift` selects targets by
host OS), so agents validate changes end to end without a Mac:

```bash
swift test                        # unit suite + rehearsed-day invariants + golden transcripts
swift run rehearse all --quiet    # both scripted days + a 20-seed sweep of randomized days
swift run rehearse canonical      # one full day, printed as a transcript of what the user sees
DP_SNAPSHOT_DIR=/tmp/shots swift test --filter WindowSnapshotTests   # macOS: render the Stats pages + Settings to PNGs
```

(on macOS the rehearsal entry point is `swift run DynamicPomodoro rehearse …`.)

A rehearsal plays a whole simulated workday through the real reducer, selector, curve and
content, prints everything the user would have seen — menu bar, notifications, break cards,
chimes, screen locks — and checks the invariants PURPOSE promises (no sound during a live call,
one lock per break at +30s, nudges once a day, picks from the right pool, …). Two days are
frozen as golden transcripts under `Tests/DynamicPomodoroTests/Fixtures/`; a change to anything
user-visible fails the golden test and is re-recorded deliberately
(`DP_REHEARSAL_RECORD=1 swift test --filter GoldenDayTests`), so the PR diff shows the user's
day changing, line by line. To watch one loop for real on a Mac, debug builds compress time:
`DP_SECONDS_PER_MINUTE=2 swift run` runs a 20-minute session in 40 seconds (persistence
auto-redirects to a scratch directory). CI runs the macOS build plus the Linux suite and sweep
on every push and PR.

## Auto-update

The app uses [Sparkle](https://sparkle-project.org) to check for new versions, prompt the user, download the new build, and relaunch. Installed clients fetch the appcast from `https://github.com/BGSoares/dynamic-pomodoro/releases/latest/download/appcast.xml` — GitHub transparently redirects this URL to the latest published release's `appcast.xml` asset, so there's no copy of the manifest committed to `main` and no GitHub Pages needed. This matches the pattern used by [Lede](https://github.com/BGSoares/lede). Clients check once every 24 hours and via the menu bar's "Check for Updates…" item.

The redirect requires the repo to be public — `releases/latest/download/<file>` returns 404 to authenticated requests on private repos.

### One-time setup (release maintainer only)

1. `brew install --cask sparkle` — provides `generate_keys` and `sign_update`.
2. Generate an EdDSA key pair:
   ```bash
   "/Applications/Sparkle.app/Contents/Resources/generate_keys"
   ```
   The private key is stored in your login Keychain; **never** commit it. Copy the printed public key.
3. Paste the public key into `build-app.sh` as `SU_PUBLIC_ED_KEY`. Commit this — the public key is meant to be public.
4. Ensure `gh auth login` is set up so `release.sh` can create GitHub releases.

### Cutting a release

Preferred (CI): tag the commit and push — `.github/workflows/release.yml` builds, signs, and publishes the release automatically.

```bash
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

The workflow uses the `SPARKLE_ED_PRIVATE_KEY` repository secret to sign the zip, so no Sparkle install or local Keychain key is needed for releases. Mirrors Lede's `tauri-action` setup.

Fallback (local): `./release.sh 1.0.1` does the same thing on your machine — builds, signs (with the Keychain key from `generate_keys`), tags, and creates the release with all three assets attached. Useful if CI is broken or you want to ship a build without pushing the tag through CI. The workflow is idempotent: if it fires on a tag that release.sh already published, it just re-uploads the assets with `--clobber`.

The build number (`CFBundleVersion`, used by Sparkle to decide whether an update is newer) defaults to the count of git commits, so it increases monotonically without manual bookkeeping.

### Zero-network variant (NoSparkle)

Each release also carries `DynamicPomodoro-NoSparkle-<version>.zip`.
That build has no updater framework, no `SU*` Info.plist keys, and no entitlements – library validation stays fully enabled and the app makes no network connections at all.
Use it on machines where auto-update (or any network activity) is unwanted.
Updates are manual: download the next release's NoSparkle zip and replace the app in `/Applications`.
The same variant builds locally via `./build-app.sh <version> <build> --no-sparkle`.

## Architecture

```
Sources/DynamicPomodoro/
├── main.swift                         # NSApplication bootstrap, menu bar, windows
├── BreakOverlayManager.swift          # Full-screen break panels, one per display
├── ResourceBundle.swift               # Bundle.module-safe resource lookup
├── Core/
│   └── PomodoroCore.swift             # Pure state machine (idle → focus → break)
├── Models/
│   ├── Settings.swift                 # UserDefaults-backed config
│   ├── Activity.swift                 # Activity model + library loader
│   └── SessionLog.swift               # JSON log in ~/Library/Application Support
├── Logic/                             # Pure, unit-testable
│   ├── DurationCurve.swift            # §3 — cosine curve + first-session rule
│   ├── BreakLogic.swift               # §4.1 — 20% with 5-min floor
│   ├── ActivitySelector.swift         # §4.3 — filter + soft rules
│   ├── Messages.swift                 # §4.5 — reminder + skip-nudge pools
│   ├── Nudges.swift                   # Task nudges on the break card (PURPOSE principle 8)
│   ├── FocusHistory.swift             # Session log → focus per day, by calendar week (Monday–Sunday)
│   ├── WeekTimeline.swift             # Session log → each day's sessions at their wall-clock hours
│   ├── UnlockGate.swift               # Unlock auto-start gate (see SPEC_UNLOCK_AUTOSTART.md)
│   ├── ScreenLockState.swift          # unknown/locked/unlocked (see SPEC_LOOP_CONTINUITY.md §3.1)
│   ├── MenuBarTitle.swift             # The status-item title string (rendered by main.swift)
│   └── TimeScale.swift                # DP_SECONDS_PER_MINUTE time compression (debug-only)
├── Rehearsal/                         # Plays whole simulated days; checks PURPOSE's promises
│   ├── DayRehearsal.swift             # The engine: real logic, synthetic clock, invariant checks
│   ├── RehearsalScript.swift          # The scripted + seeded days
│   ├── Transcript.swift               # Event model + rendering
│   ├── RehearsalCLI.swift             # `rehearse` command-line entry
│   └── SeededRNG.swift                # SplitMix64, for deterministic replay
├── Services/
│   ├── TimerEngine.swift              # Drives PomodoroCore, owns the ticker
│   ├── NotificationService.swift      # UNUserNotificationCenter
│   ├── ScreenLockService.swift        # Locks the screen 30s into a break
│   ├── ScreenLockMonitor.swift        # Tracks ScreenLockState from the lock/unlock notification pair
│   ├── SoundService.swift             # System sound chimes
│   ├── CallDetectionService.swift     # CoreAudio-based live-call probe
│   ├── UpdaterService.swift           # Sparkle wrapper (auto-update)
│   └── AutoStartService.swift         # Unlock + skip auto-start countdown, HUD panel (renamed from UnlockAutoStartService)
├── Views/                             # SwiftUI
│   ├── MainWindowView.swift
│   ├── IdleView.swift
│   ├── FocusView.swift
│   ├── BreakOverlayView.swift         # Full-screen break overlay (fade-in prep)
│   ├── BreakMirrorView.swift          # Placeholder in main window during break
│   ├── BreakPendingView.swift         # Owed break waiting for a call to end
│   ├── HoldToSkipButton.swift
│   ├── SettingsView.swift
│   ├── StatsView.swift                # Stats window: totals page (focus hours per day) + page switch
│   ├── WeekTimelineView.swift         # Stats window: timeline page (this week and last, hour by hour)
│   └── CountdownHUDView.swift         # Auto-start countdown card (unlock and skip triggers)
└── Resources/
    └── activities.json                # The curated activity library
```

Data persisted locally:

- **Settings** → `UserDefaults` (domain: your user account)
- **Session log** → `~/Library/Application Support/DynamicPomodoro/sessions.json`

## Spec implementation notes

- **§3.2 curve vs. table.** The spec gives an explicit cosine formula, then an illustrative table below it. The two don't agree (e.g. formula gives 25 min at 10:30; table says "~30"). I followed the formula, since it's the authoritative code block. If you want a flatter peak matching the table, swap the cosine for e.g. a widened plateau function — one place to change: `Logic/DurationCurve.swift`.
- **Two minimums, one peak.** The curve's floor is two settings, not one: *Minimum at start* and *Minimum at end*. Each half of the workday is its own half-cosine from its floor up to the shared maximum at the midpoint, so with equal floors the curve is the original symmetric bell, and with a higher end floor the afternoon tapers less steeply without the morning changing at all. The first session of the day is the start minimum (it is the warm-up, whatever the clock says); before the workday the curve sits at the start minimum, after it at the end minimum. A `minFocusMinutes` value stored before the split (2026-10-05) seeds both floors on first launch so the curve doesn't move on upgrade.
- **§3.5 interruption handling.** Abandon discards the session entirely — no pause state, per spec. A confirmation dialog guards the abandon button.
- **§4.3 selection filter relaxation.** If the hard filter (band + time-of-day) produces an empty pool, the selector relaxes the duration-band constraint first (keeping time-of-day), then falls back to the full library, to guarantee the break always has *something*. Documented inline in `ActivitySelector.swift`.
- **§4.5 message frequency.** Reminder line rotates once per calendar day (deterministic by date) and is shown on every break that day. Logic lives in `Logic/Messages.swift`.
- **Break-card nudges.** A nudge is one line (an ask, e.g. eat something before you leave) plus the reason it matters, with a time attached; it rides the earliest break that starts at or after that time, at most once a day, and takes the same slot the daily reminder line occupies rather than adding a surface (PURPOSE principle 8). No notification, no chime, no completion state, no log entry. Delivery is *derived*, not persisted: `Nudges.assign` re-folds today's break start times (`SessionLogStore.shownBreakStartsToday` – only breaks that actually put a card on screen, so a break capped out by a long call can't spend one) and hands each break the most recently due nudge still unspent, so a second due nudge falls to the next break instead of being dropped. If no break starts after a nudge's time that day, the nudge simply doesn't fire – deliberately, since anything louder is the reminders app this exists to avoid. To add or edit one: `Logic/Nudges.swift`, same as the activity library. This is not the task-manager integration ruled out in §8 – nothing syncs, and the app never learns whether the thing got done. The library has been empty since 2026-10-05: the first nudge (muesli after 16:20) didn't stick and was removed; the mechanism stays for the next one.
- **Unlock and skip auto-start countdown.** On a macOS unlock, or on a completed hold-to-skip, if the app is idle and (for the unlock trigger) a break ended within the last 20 minutes (tunable, not shown in `SettingsView`), a floating HUD counts down from 15s (also tunable) and auto-starts the next focus session via the same `startFocus()` path a manual start uses. Esc (captured locally by the HUD panel — no global monitor, no Input Monitoring prompt) or a click on the menu-bar item cancels it — which also opens the main window, since the cancel is a decision to not start now. Both triggers are call-gated: a live call drops the offer entirely, with no suppression written. Full design in `SPEC_UNLOCK_AUTOSTART.md` and `SPEC_LOOP_CONTINUITY.md` §2.
- **Breaks defer during calls.** If the mic is in use when a focus session ends (any meeting app — Meet, Zoom, FaceTime… — holds the input stream open even while muted), the break waits in a `breakPending` state and starts on its own when the call ends. Bounded by a 30-minute cap (then logged as `breakSkipped`, and never auto-starts the next session). "Start break now" overrides the wait and lives in the status menu (shown only during `breakPending`) rather than a window, since principle 7 forbids opening a window while a call is live. Detection is `CallDetectionService` (CoreAudio device state; no capture, no permission prompt).
- **Window discipline.** The main window opens only when it has a decision to offer: a break that completed while the screen was known unlocked (`ScreenLockMonitor`, tracking `.unknown`/`.locked`/`.unlocked` — launch counts as `.unknown`, never treated as unlocked), or a cancelled countdown. It never opens at launch or during a focus session, and closing it just hides it, same as before. The menu bar carries the rest: the status item reads `Start 32m` while idle (recomputed on a 60s idle-only coalesced timer, plus Settings/wake/activate), and one click starts that session; right-click (or a click while a countdown is running) opens the menu or cancels it respectively. Full design in `SPEC_LOOP_CONTINUITY.md`.
- **Never interrupt a meeting (PURPOSE principle 7).** While `CallDetectionService.isOnCall()` reads true, nothing new appears or sounds: no break-end foreground, no countdown HUD, no countdown-cancel window. The full-screen break overlay needs no gate – a break never *starts* during a call (it waits in `breakPending`, see `SPEC_LOOP_CONTINUITY.md` §6.4) – but a call can begin during a break, so the break's end is silenced (no Ping, silent banner) and the 30-second screen lock is withheld, for good, if the mic went live before it fired; the break itself still runs to its end. The one exception is anything explicitly requested, chiefly "Start break now", which runs in full – lock included – regardless of the call signal (`PomodoroState.breakOverridesCall`).
- **Abandon from the menu bar.** §3.5's discard, reachable without a window. It had to go somewhere other than the main window, because §4.2 hides that window for the whole of a focus session — so the only surface that exists mid-session is the status menu. The item is hidden outside `.focus`, same level-triggered treatment as "Start break now". Confirmed with an `NSAlert` whose default button is *Continue*, not *Abandon*: this is not friction in principle 4's sense (that rule is about breaks, and abandoning a focus session is not a break skip) but the session is discarded outright with no undo, and a menu is an easy thing to mis-click. Copy for both surfaces lives in one place, `AbandonPrompt`.
- **Stats window.** Focus hours per day over the last four calendar weeks – the readout the §10 review below has always assumed you'd get by loading `sessions.json` into a notebook. Its own window, not a phase of the main one, because the main window hides during focus and a reference view that vanishes when you start working is no use. `Logic/FocusHistory.swift` does the folding and is pure; `Views/StatsView.swift` only draws. Whole calendar weeks rather than a rolling 28 days, so a week total means a week someone recognises – the price is a partial current week, which the chart shows as empty slots rather than as zeros. Per-day totals come from `DailyStats.contribution`, the same function behind the idle screen's "today" footer, so the two can't disagree. One control, the **break time** button: a click stacks the day's completed breaks on top of its focus and the axis, totals and week footers follow – focus alone answers "how much did I get done", focus plus break answers "how close was that to a working day", and the second question is asked of desk time, not of focus. Skipped breaks add nothing, because the break didn't happen. Which readout is showing is remembered across launches (`@AppStorage`), and the two are named in the pure layer (`StatsMeasure`) so the bars, the axis and the header can't disagree about what is plotted. Deliberately *only* a readout: no goal line, no streak, no target, no week-over-week comparison, no congratulation (PURPOSE: "not a coaching app", and "more pomodoros" is explicitly not the success metric) – the break-time button adds a number, and says nothing about it. Weeks on both pages run Monday to Sunday by definition (`WeekGrid`), whatever the locale's first weekday, because that is the week hours get counted against.
- **Stats window, timeline page.** The second page of the same window: this week and last, Monday to Sunday, one row per day, with every focus session and break drawn at the wall-clock hour it actually ran, and each day labelled with its first start and last end. It exists because hours now have to be reported at work, and "when did I start, where did I pause, when did I stop" is a question the totals page cannot answer and `sessions.json` answers only with a text editor. `Logic/WeekTimeline.swift` does the folding (pure; skipped breaks are not drawn, the same rule the totals use; a span past midnight is clipped to its start day) and `Views/WeekTimelineView.swift` draws. One axis covers both weeks – the configured workday, widened on whole hours to the earliest and latest thing logged – so switching weeks never rescales the day. Completed focus is solid, abandoned focus hollow, breaks the lighter band; hovering a block gives its exact times. Same posture as the totals page: a readout, not a score – no target hours, no comparison.
- **Open Q #4** (first-session reset boundary) is currently **calendar midnight**, not workday-start. Easy to switch in `SessionLogStore.hasCompletedFocusToday`.
- **Open Q #1** decided in favor of **native Swift/SwiftUI** over Electron — better battery, cleaner menu bar integration, and the scope is small enough that Electron's build-speed advantage doesn't matter.
- **Open Q #2**: library is 34 activities across 7 categories, 2 duration bands, 4 time-of-day slots. The original claim here — "enough variety that recency + category rotation keep back-to-back breaks distinct" — was true of the short band and false of the medium one: it shipped with 2 medium activities, so every long morning break served `stairs` and long end-of-day breaks had no pool at all. Both soft rules in `ActivitySelector` are no-ops when they would empty the pool, so a thin cell silently disables the rules meant to keep breaks distinct. Fixed by taking the medium band to 10; `bundledLibraryMeetsPoolFloorInEveryCell` now holds every `(band, time-of-day)` cell to ≥6 activities across ≥3 categories. Measurement and reasoning in [`SPEC_RECOVERY_MESSAGING.md`](SPEC_RECOVERY_MESSAGING.md) §1.1.
- **Open Q #3**: no daily session cap. Can be added to `PomodoroReducer.reduce`'s `.startFocus` case if needed.

## Tests

Unit tests for the pure logic live in `Tests/DynamicPomodoroTests/`, written with [swift-testing](https://github.com/swiftlang/swift-testing).

Bare Command Line Tools ship no testing runtime (neither XCTest nor swift-testing).
To run tests locally, use a full toolchain — Xcode, or the swift.org toolchain via [swiftly](https://www.swift.org/install/):

```bash
brew install swiftly && swiftly init --no-modify-profile
~/.swiftly/bin/swift test
```

CI runs the suite on every push and PR (`.github/workflows/ci.yml`).

## Packaging as a real .app

`./build-app.sh` builds the SPM binary, wraps it in a proper `.app` bundle (Info.plist, entitlements, icon, Sparkle.framework, ad-hoc code signing), and installs it to `/Applications` — see [Cutting a release](#cutting-a-release) above for the tag-and-push flow that runs this in CI.

## Not built (per spec §8)

- Cloud sync, accounts, mobile
- Calendar integration / auto-pause
- Custom user activities
- Task-manager integration
- Adaptive learning (deferred to v1.1 per §9)

## What to dogfood over the next two weeks (§10)

1. Session completion rate — aim >80%
2. Perceived focus quality — weekly 1–5 rating, aim ≥4
3. Curve override rate — aim <10% (but note: v1 has no "override" UI, since it's not in the spec; if overrides are common in practice, add a duration stepper on the idle screen)
4. Break completion rate — aim >60%

Raw data is in `sessions.json` (ISO-8601 dates, one entry per focus/break transition). Easy to load into a notebook for the 2-week review. Metric 1 is also readable straight from the menu bar's **Stats** window, which plots focus hours per day over the last four calendar weeks; its break-time button adds the breaks taken, for the separate question of how a day compared with a working day.
