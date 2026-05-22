#!/usr/bin/env bash
#
# dynamic-pomodoro.sh — a macOS-native sketch of the dynamic pomodoro loop.
#
# What this is: a single shell script that demonstrates the *idea* of the app
# (cosine-curve session duration + prescribed break + screen lock) using only
# tools already on the Mac — bash, python3, osascript, pmset, jq.
#
# What this is NOT: a replacement for the Swift app. It cannot do the
# full-screen multi-display break overlay or the 15-second hold-to-skip,
# which are exactly the friction mechanisms that make the real app work.
# This sketch keeps the timing/notification half and stubs the overlay half
# with a system notification + screen lock at 30s.
#
# Usage:
#   ./sketches/dynamic-pomodoro.sh              # loop forever
#   ./sketches/dynamic-pomodoro.sh --once       # one focus+break cycle
#   ./sketches/dynamic-pomodoro.sh --dry-run    # print plan, don't sleep
#
# State + log live in:
#   ~/Library/Application Support/DynamicPomodoroSketch/

set -euo pipefail
umask 077                        # new files in $SUPPORT_DIR default to 600

# ---- harden PATH and resolve binaries to absolute paths ----
# Reset PATH so a hijacked parent shell can't redirect us to a planted binary.
# Then resolve each tool once via `command -v` and use the absolute path
# everywhere — no more bare `jq` / `osascript` lookups at call time.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

require_bin() {
  local var=$1 name=$2 path
  path=$(command -v "$name" 2>/dev/null || true)
  if [[ -z "$path" || ! -x "$path" ]]; then
    echo "missing required binary on PATH: $name" >&2
    exit 127
  fi
  printf -v "$var" '%s' "$path"
}

require_bin JQ        jq
require_bin PYTHON3   python3
require_bin OSASCRIPT osascript
require_bin PMSET     pmset

# ---- settings (mirror the Swift app's UserDefaults defaults) ----
WORKDAY_START_MIN=$((9 * 60))    # 09:00
WORKDAY_END_MIN=$((18 * 60))     # 18:00
MIN_FOCUS_MIN=20
MAX_FOCUS_MIN=40
SCREEN_LOCK_DELAY_S=30           # lock screen N seconds into the break
BREAK_MIN=5                      # fixed break length for the sketch

# ---- paths ----
SUPPORT_DIR="$HOME/Library/Application Support/DynamicPomodoroSketch"
STATE_FILE="$SUPPORT_DIR/state"
LOG_FILE="$SUPPORT_DIR/sessions.jsonl"
ACTIVITIES_JSON="$(cd "$(dirname "$0")/.." && pwd)/Sources/DynamicPomodoro/Resources/activities.json"
mkdir -p "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"         # state/log are not for other accounts
touch "$STATE_FILE" "$LOG_FILE"
chmod 600 "$STATE_FILE" "$LOG_FILE"

# ---- validate JSON inputs/outputs ----
# Read-side: refuse to start on a malformed activities.json (would otherwise
# silently fall back to the built-in line and hide the corruption).
if [[ -f "$ACTIVITIES_JSON" ]]; then
  "$JQ" empty "$ACTIVITIES_JSON" >/dev/null 2>&1 \
    || { echo "activities.json is malformed; refusing to start" >&2; exit 1; }
fi
# Write-side: if the existing log is already corrupt, surface it now rather
# than appending more lines on top of bad data.
if [[ -s "$LOG_FILE" ]]; then
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    printf '%s\n' "$_line" | "$JQ" empty >/dev/null 2>&1 \
      || { echo "sessions.jsonl contains invalid JSON; refusing to append" >&2; exit 1; }
  done < "$LOG_FILE"
fi

DRY_RUN=0
ONCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --once)    ONCE=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ---- duration curve ----
# Mirrors DurationCurve.swift: first session of day = min, otherwise a cosine
# peaking at midday between MIN and MAX.
focus_duration_minutes() {
  local now_min=$1
  local is_first=$2
  "$PYTHON3" - "$now_min" "$is_first" \
    "$WORKDAY_START_MIN" "$WORKDAY_END_MIN" \
    "$MIN_FOCUS_MIN" "$MAX_FOCUS_MIN" <<'PY'
import math, sys
now, first, start, end, lo, hi = map(int, sys.argv[1:])
if first or now < start or now > end:
    print(lo); sys.exit()
mid = (start + end) / 2
half = (end - start) / 2
ratio = min(abs(now - mid) / half, 1.0)
weight = 0.5 * (1 + math.cos(math.pi * ratio))
print(round(lo + (hi - lo) * weight))
PY
}

minutes_since_midnight() {
  local h m
  h=$(date +%H); m=$(date +%M)
  echo $(( 10#$h * 60 + 10#$m ))
}

is_first_session_today() {
  local today last
  today=$(date +%F)
  last=$(cat "$STATE_FILE" 2>/dev/null || echo "")
  [[ "$last" != "$today" ]]
}

mark_session_today() {
  date +%F > "$STATE_FILE"
}

# ---- activity selection ----
pick_activity() {
  if [[ ! -f "$ACTIVITIES_JSON" ]]; then
    # Running outside the repo — use a single built-in line.
    echo "Stand up. Walk to the furthest window. Look at something 20+ metres away for 60 seconds."
    return
  fi
  local hour time_band
  hour=$(date +%H); hour=$((10#$hour))
  if   (( hour < 11 )); then time_band="morning"
  elif (( hour < 14 )); then time_band="midday"
  elif (( hour < 17 )); then time_band="afternoon"
  else                       time_band="end_of_day"
  fi
  "$JQ" -r --arg t "$time_band" '
    [.[] | select(.suitable_times | index($t))] as $candidates
    | if ($candidates | length) == 0 then .[0] else $candidates[(now | floor) % ($candidates | length)] end
    | .instruction
  ' "$ACTIVITIES_JSON"
}

# ---- macOS primitives ----
notify() {
  local title=$1 body=$2
  if (( DRY_RUN )); then echo "[notify] $title — $body"; return; fi
  "$OSASCRIPT" -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\""
}

show_break_dialog() {
  local body=$1
  if (( DRY_RUN )); then echo "[dialog] $body"; return; fi
  # Non-blocking-ish: give the user a chance to dismiss, but auto-dismiss after 20s
  # so the break itself isn't held up by the modal.
  "$OSASCRIPT" <<APPLESCRIPT >/dev/null 2>&1 || true
    tell application "System Events"
      activate
      display dialog "$body" with title "Break — recovery" buttons {"OK"} default button "OK" giving up after 20
    end tell
APPLESCRIPT
}

lock_screen() {
  if (( DRY_RUN )); then echo "[lock-screen]"; return; fi
  "$PMSET" displaysleepnow
}

sleep_minutes() {
  local m=$1
  if (( DRY_RUN )); then echo "[sleep] ${m}m"; return; fi
  sleep $(( m * 60 ))
}

log_session() {
  local kind=$1 minutes=$2 line
  # Build with jq so the output is guaranteed to be valid JSON regardless of
  # what's in the inputs (quotes, backslashes, etc.).
  line=$("$JQ" -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg kind "$kind" \
    --argjson minutes "$minutes" \
    '{ts:$ts, kind:$kind, minutes:$minutes}')
  # Defence in depth: validate before append so a partial write never lands.
  printf '%s\n' "$line" | "$JQ" empty >/dev/null 2>&1 \
    || { echo "refusing to append invalid JSON to sessions.jsonl" >&2; return 1; }
  printf '%s\n' "$line" >> "$LOG_FILE"
}

# ---- main loop ----
run_one_cycle() {
  local now_min first focus
  now_min=$(minutes_since_midnight)
  if is_first_session_today; then first=1; else first=0; fi
  focus=$(focus_duration_minutes "$now_min" "$first")

  echo "→ focus ${focus}m  (now=$(date +%H:%M)  first-of-day=$first)"
  notify "Focus — ${focus}m" "On the bike. See you at the top."
  mark_session_today
  sleep_minutes "$focus"
  log_session "focus" "$focus"

  local activity
  activity=$(pick_activity)
  echo "→ break ${BREAK_MIN}m  activity: $activity"
  notify "Break — ${BREAK_MIN}m" "$activity"
  show_break_dialog "$activity"

  # Lock the screen partway into the break so the chair-impulse fails.
  if (( DRY_RUN )); then
    echo "[sleep] ${SCREEN_LOCK_DELAY_S}s, then lock"
  else
    sleep "$SCREEN_LOCK_DELAY_S"
  fi
  lock_screen
  sleep_minutes "$BREAK_MIN"
  log_session "break" "$BREAK_MIN"
}

if (( ONCE )); then
  run_one_cycle
else
  while true; do run_one_cycle; done
fi
