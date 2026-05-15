# Dynamic Pomodoro

> **Routine review agent:** the rotating Question 2 of the in-app feedback flow lives in [`Sources/DynamicPomodoro/Resources/feedback_question.json`](Sources/DynamicPomodoro/Resources/feedback_question.json). Read [`Sources/DynamicPomodoro/Resources/AGENT_README.md`](Sources/DynamicPomodoro/Resources/AGENT_README.md) for the schema and rules. User responses log to `~/Library/Application Support/DynamicPomodoro/feedback.json`.

macOS menu-bar pomodoro timer with session durations that follow a bell curve across the workday, plus active break prompts drawn from a curated activity library.

Built to the v0.2 spec in `spec.md` (your spec document). Native Swift / SwiftUI + AppKit, no dependencies.

## Build & run

```bash
swift run
```

The app launches into the menu bar (no Dock icon). Look for the timer icon in the upper-right of the screen. First run shows onboarding.

## Auto-update

The app uses [Sparkle](https://sparkle-project.org) to check for new versions, prompt the user, download the new build, and relaunch. Installed clients fetch the appcast from `https://github.com/BGSoares/dynamic-pomodoro/releases/latest/download/appcast.xml` — GitHub transparently redirects this URL to the latest published release's `appcast.xml` asset, so there's no copy of the manifest committed to `main` and no GitHub Pages needed. This matches the pattern used by [Lede](https://github.com/BGSoares/lede). Clients check once every 24 hours and via the menu bar's "Check for Updates…" item.

Because this repo is private, Sparkle's anonymous GETs to `github.com` return 404. A fine-grained GitHub PAT (read-only, scoped to this repo's Contents) is baked into `Info.plist` at build time and sent as a `Bearer` token on every request via Sparkle's `httpHeaders`. The PAT is **never** committed to source — GitHub's secret-scanning would auto-revoke it. It only lives in (a) the binary on the maintainer's Mac and (b) the `GH_PRIVATE_REPO_PAT` GitHub Actions secret.

### One-time setup (release maintainer only)

1. `brew install --cask sparkle` — provides `generate_keys` and `sign_update`.
2. Generate an EdDSA key pair:
   ```bash
   "/Applications/Sparkle.app/Contents/Resources/generate_keys"
   ```
   The private key is stored in your login Keychain; **never** commit it. Copy the printed public key.
3. Paste the public key into `build-app.sh` as `SU_PUBLIC_ED_KEY`. Commit this — the public key is meant to be public.
4. Generate a fine-grained GitHub PAT at <https://github.com/settings/personal-access-tokens/new>:
   - Repository access → **Only select repositories** → `dynamic-pomodoro`
   - Repository permissions → **Contents: Read-only**
   - Copy the `ghp_...` token. Set `GITHUB_PAT` in your shell profile (e.g. `~/.zprofile`) so `build-app.sh` picks it up locally:
     ```bash
     export GITHUB_PAT="ghp_..."
     ```
   - Add the same value as repository secret `GH_PRIVATE_REPO_PAT` (`gh secret set GH_PRIVATE_REPO_PAT`) so the release workflow can bake it in too.
5. Ensure `gh auth login` is set up so `release.sh` can create GitHub releases.

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
├── Models/
│   ├── Settings.swift                 # UserDefaults-backed config
│   ├── Activity.swift                 # Activity model + library loader
│   └── SessionLog.swift               # JSON log in ~/Library/Application Support
├── Logic/                             # Pure, unit-testable
│   ├── DurationCurve.swift            # §3 — cosine curve + first-session rule
│   ├── BreakLogic.swift               # §4.1 — 20% with 5-min floor
│   ├── ActivitySelector.swift         # §4.3 — filter + soft rules
│   └── Messages.swift                 # §4.5 — reminder pool
├── Services/
│   ├── TimerController.swift          # State machine (idle → focus → break)
│   ├── NotificationService.swift      # UNUserNotificationCenter
│   └── UpdaterService.swift           # Sparkle wrapper (auto-update)
├── Views/                             # SwiftUI
│   ├── MainWindowView.swift
│   ├── IdleView.swift
│   ├── FocusView.swift
│   ├── BreakOverlayView.swift         # Full-screen break overlay (fade-in prep)
│   ├── BreakMirrorView.swift          # Placeholder in main window during break
│   ├── OnboardingView.swift
│   ├── SettingsView.swift
│   └── CurvePreviewView.swift
└── Resources/
    └── activities.json                # 20 built-in activities
```

Data persisted locally:

- **Settings** → `UserDefaults` (domain: your user account)
- **Session log** → `~/Library/Application Support/DynamicPomodoro/sessions.json`

## Spec implementation notes

- **§3.2 curve vs. table.** The spec gives an explicit cosine formula, then an illustrative table below it. The two don't agree (e.g. formula gives 25 min at 10:30; table says "~30"). I followed the formula, since it's the authoritative code block. If you want a flatter peak matching the table, swap the cosine for e.g. a widened plateau function — one place to change: `Logic/DurationCurve.swift`.
- **§3.5 interruption handling.** Abandon discards the session entirely — no pause state, per spec. A confirmation dialog guards the abandon button.
- **§4.3 selection filter relaxation.** If the hard filter (band + time-of-day + enabled) produces an empty pool (e.g. user disables too many categories), the selector relaxes the duration-band constraint first, then disabled-only, to guarantee the break always has *something*. Documented inline in `ActivitySelector.swift`.
- **§4.5 message frequency.** Reminder messages are shown only on first break of the calendar day OR immediately after a skipped break. Logic lives in `TimerController.showBreakPrompt`.
- **Open Q #4** (first-session reset boundary) is currently **calendar midnight**, not workday-start. Easy to switch in `SessionLogStore.hasEntryToday`.
- **Open Q #1** decided in favor of **native Swift/SwiftUI** over Electron — better battery, cleaner menu bar integration, and the scope is small enough that Electron's build-speed advantage doesn't matter.
- **Open Q #2**: starter library is 20 activities across 5 categories, 2 duration bands, 4 time-of-day slots. Enough variety that recency + category rotation keep back-to-back breaks distinct.
- **Open Q #3**: no daily session cap. Can be added to `TimerController.startFocus` if needed.

## Tests

Unit tests for the pure logic live in `Tests/DynamicPomodoroTests/`. They use `XCTest`, which requires **Xcode** (not just Command Line Tools) to run:

```bash
swift test          # requires Xcode installed
```

The core math (curve, break duration, selector rules) is also covered by an ad-hoc smoke script used during development.

## Packaging as a real .app

For daily use you probably want a proper `.app` bundle so notifications include your app name and macOS treats it as a real application. Two paths:

1. **Wrap in an Xcode project** — `File > New > Project… > macOS App`, then drag `Sources/DynamicPomodoro/*` in and set `LSUIElement = YES` in Info.plist to keep it menu-bar-only.
2. **Stay with SPM** and build a bundle post-hoc with a small script that wraps the SPM binary in an `.app` directory with Info.plist + entitlements.

For personal daily use, option 1 is less effort.

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
