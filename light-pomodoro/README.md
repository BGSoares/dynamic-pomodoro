# light-pomodoro

A dynamic pomodoro loop for macOS, in one Bash script.

Focus sessions follow a cosine curve across your workday — short at the
edges, longer around midday — instead of a fixed 25 minutes. Each break
comes with a specific prescribed activity (stretch, eye-rest, walk,
breathwork) drawn from `activities.json`. The screen locks 30 seconds
into the break so the impulse to sit through it fails by default.

## What it does

- Computes today's focus duration from a cosine curve between
  `MIN_FOCUS_MIN` and `MAX_FOCUS_MIN`, peaking at the workday midpoint
- First session of the day is always the minimum (warm-up)
- Picks an activity from `activities.json`, filtered by time-of-day band
- Shows a macOS notification + dialog with the activity
- Calls `pmset displaysleepnow` 30s into the break to lock the screen
- Appends one JSON line per session to `~/Library/Application Support/LightPomodoro/sessions.jsonl`

## What it deliberately does not do

- No multi-display blackout overlay
- No 15-second hold-to-skip; the dialog is OK-or-auto-dismiss after 20s
- No menu-bar UI, settings window, or onboarding

These omissions are the gap between a shell script and a native AppKit
app. If you want those, the upstream Swift app at
<https://github.com/BGSoares/dynamic-pomodoro> is the place.

## Requirements

macOS, plus:

- `bash` (system version is fine)
- `python3` (used for the cosine math)
- `jq` — `brew install jq`
- `osascript`, `pmset` — preinstalled on macOS

## Install

```sh
git clone <this-repo> light-pomodoro
cd light-pomodoro
chmod 700 dynamic-pomodoro.sh
```

That's it. No build step.

## Usage

```sh
./dynamic-pomodoro.sh              # loop forever
./dynamic-pomodoro.sh --once       # one focus + break cycle
./dynamic-pomodoro.sh --dry-run    # print the plan without sleeping
```

Stop the loop with Ctrl-C. The session log is preserved across runs.

## Customise

The four numbers that matter live at the top of the script:

```sh
WORKDAY_START_MIN=$((9 * 60))   # 09:00
WORKDAY_END_MIN=$((18 * 60))    # 18:00
MIN_FOCUS_MIN=20
MAX_FOCUS_MIN=40
```

To add or change break activities, edit `activities.json`. The shape of
each entry is:

```json
{
  "id": "neck_rolls",
  "name": "Neck rolls",
  "instruction": "Stand tall. Slow circles — 5 each way. Breathe through the nose.",
  "suitable_times": ["morning", "midday", "afternoon", "end_of_day"]
}
```

`category`, `band`, and `energy` are accepted but unused by this script.

## Files

| Path | What |
|---|---|
| `dynamic-pomodoro.sh` | the script |
| `activities.json` | prescribed break activities |
| `~/Library/Application Support/LightPomodoro/state` | last-session date (one line) |
| `~/Library/Application Support/LightPomodoro/sessions.jsonl` | append-only session log |

State and log live outside the repo so updating the script doesn't touch
them. The script self-restricts permissions: `700` on the support dir,
`600` on state and log.

## Run on login

Wrap the script in a `LaunchAgent` plist if you want it to start with
your session — `man launchd.plist` covers the format. Intentionally not
shipped here; the goal is one script + one JSON file.

## Credits

Curve, activities, and the principle that rest is part of the work are
borrowed from <https://github.com/BGSoares/dynamic-pomodoro>.
