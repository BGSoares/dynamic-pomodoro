# Dynamic Pomodoro

macOS menu-bar pomodoro timer with session durations that follow a bell curve across the workday, plus active break prompts drawn from a curated activity library.

Built to a v0.2 product spec kept outside this repo. Native Swift / SwiftUI + AppKit.
Only runtime dependency is [Sparkle](https://sparkle-project.org) (auto-update).

## Build & run

```bash
swift run
```

The app launches into the menu bar (no Dock icon). Look for the timer icon in the upper-right of the screen. No onboarding — first launch lands on Idle with sensible defaults.

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

Fallback (local): `./release.sh 1.0.1` does the same thing on your machine — builds, signs (with the Keychain key from `generate_keys`), tags, and creates the release with both assets attached. Useful if CI is broken or you want to ship a build without pushing the tag through CI. The workflow is idempotent: if it fires on a tag that release.sh already published, it just re-uploads the assets with `--clobber`.

The build number (`CFBundleVersion`, used by Sparkle to decide whether an update is newer) defaults to the count of git commits, so it increases monotonically without manual bookkeeping.

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
│   └── Messages.swift                 # §4.5 — reminder + skip-nudge pools
├── Services/
│   ├── TimerEngine.swift              # Drives PomodoroCore, owns the ticker
│   ├── NotificationService.swift      # UNUserNotificationCenter
│   ├── ScreenLockService.swift        # Locks the screen 30s into a break
│   ├── SoundService.swift             # System sound chimes
│   └── UpdaterService.swift           # Sparkle wrapper (auto-update)
├── Views/                             # SwiftUI
│   ├── MainWindowView.swift
│   ├── IdleView.swift
│   ├── FocusView.swift
│   ├── BreakOverlayView.swift         # Full-screen break overlay (fade-in prep)
│   ├── BreakMirrorView.swift          # Placeholder in main window during break
│   ├── HoldToSkipButton.swift
│   └── SettingsView.swift
└── Resources/
    └── activities.json                # 26 built-in activities
```

Data persisted locally:

- **Settings** → `UserDefaults` (domain: your user account)
- **Session log** → `~/Library/Application Support/DynamicPomodoro/sessions.json`

## Spec implementation notes

- **§3.2 curve vs. table.** The spec gives an explicit cosine formula, then an illustrative table below it. The two don't agree (e.g. formula gives 25 min at 10:30; table says "~30"). I followed the formula, since it's the authoritative code block. If you want a flatter peak matching the table, swap the cosine for e.g. a widened plateau function — one place to change: `Logic/DurationCurve.swift`.
- **§3.5 interruption handling.** Abandon discards the session entirely — no pause state, per spec. A confirmation dialog guards the abandon button.
- **§4.3 selection filter relaxation.** If the hard filter (band + time-of-day) produces an empty pool, the selector relaxes the duration-band constraint first (keeping time-of-day), then falls back to the full library, to guarantee the break always has *something*. Documented inline in `ActivitySelector.swift`.
- **§4.5 message frequency.** Reminder line rotates once per calendar day (deterministic by date) and is shown on every break that day. Logic lives in `Logic/Messages.swift`.
- **Open Q #4** (first-session reset boundary) is currently **calendar midnight**, not workday-start. Easy to switch in `SessionLogStore.hasCompletedFocusToday`.
- **Open Q #1** decided in favor of **native Swift/SwiftUI** over Electron — better battery, cleaner menu bar integration, and the scope is small enough that Electron's build-speed advantage doesn't matter.
- **Open Q #2**: starter library is 26 activities across 7 categories, 2 duration bands, 4 time-of-day slots. Enough variety that recency + category rotation keep back-to-back breaks distinct.
- **Open Q #3**: no daily session cap. Can be added to `PomodoroReducer.reduce`'s `.startFocus` case if needed.

## Tests

Unit tests for the pure logic live in `Tests/DynamicPomodoroTests/`. They use `XCTest`, which requires **Xcode** (not just Command Line Tools) to run:

```bash
swift test          # requires Xcode installed
```

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

Raw data is in `sessions.json` (ISO-8601 dates, one entry per focus/break transition). Easy to load into a notebook for the 2-week review.
