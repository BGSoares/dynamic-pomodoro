# Dynamic Pomodoro

macOS menu-bar pomodoro timer with session durations that follow a bell curve across the workday, plus active break prompts drawn from a curated activity library.

Built to the v0.2 spec in `spec.md` (your spec document). Native Swift / SwiftUI + AppKit, no dependencies.

## Build & run

```bash
swift run
```

The app launches into the menu bar (no Dock icon). Look for the timer icon in the upper-right of the screen. First run shows onboarding.

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
│   └── NotificationService.swift      # UNUserNotificationCenter
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
