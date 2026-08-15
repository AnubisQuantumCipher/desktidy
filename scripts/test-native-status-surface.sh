#!/bin/bash
# Prove the exact native status content can be inspected without the live Desktop.
set -euo pipefail

APP="${1:?usage: test-native-status-surface.sh /path/to/DeskTidy.app}"
CAPTURE_OUT="${2:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$(mktemp -d /private/tmp/desktidy-status-surface.XXXXXX)"
TITLE="DeskTidy Status Preview"
CAPTURE="${CAPTURE_OUT:-$FIXTURE/status-preview.png}"
PID=""
cleanup() {
  rc=$?
  trap - EXIT
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$PID" 2>/dev/null; then
      echo "status-surface: preview did not terminate; forcing cleanup" >&2
      kill -KILL "$PID" 2>/dev/null || true
      rc=1
    else
      echo "NATIVE_STATUS_SURFACE_CLEANUP=PASS pid=$PID"
    fi
  fi
  rm -rf "$FIXTURE"
  exit "$rc"
}
trap cleanup EXIT

[[ -x "$APP/Contents/MacOS/DeskTidy" ]] || { echo "status-surface: missing app executable" >&2; exit 2; }
if [[ -n "$CAPTURE_OUT" && "$CAPTURE_OUT" != /private/tmp/* ]]; then
  echo "status-surface: capture must be under /private/tmp" >&2
  exit 2
fi
[[ ! -e "$CAPTURE" ]] || { echo "status-surface: refusing to overwrite capture" >&2; exit 2; }
mkdir -p "$FIXTURE/target" "$FIXTURE/agents" "$FIXTURE/app-support"
mkdir -p "$(dirname "$CAPTURE")"
printf '%s\n' '{}' > "$FIXTURE/launchd-state.json"

open -n -g \
  --env DESKTIDY_TARGET_DIR="$FIXTURE/target" \
  --env DESKTIDY_AGENTS_DIR="$FIXTURE/agents" \
  --env DESKTIDY_APP_DIR="$FIXTURE/app-support" \
  --env DESKTIDY_LAUNCHD_STATE_FILE="$FIXTURE/launchd-state.json" \
  --stdout "$FIXTURE/stdout.log" \
  --stderr "$FIXTURE/stderr.log" \
  "$APP" --args --ui-preview

for _ in $(seq 1 20); do
  PID="$(pgrep -f "^$APP/Contents/MacOS/DeskTidy --ui-preview$" | head -1 || true)"
  [[ -n "$PID" ]] && break
  sleep 1
done
[[ -n "$PID" ]] || { echo "status-surface: app did not remain running" >&2; exit 1; }

probe=""
for _ in $(seq 1 20); do
  set +e
  probe="$(swift "$REPO/scripts/window-probe.swift" "$PID" "$TITLE" 2>&1)"
  rc=$?
  set -e
  [[ $rc -eq 0 ]] && break
  sleep 1
done
printf '%s\n' "$probe"
[[ $rc -eq 0 ]] || {
  echo "status-surface: expected preview window not observed" >&2
  [[ -s "$FIXTURE/stderr.log" ]] && sed -n '1,120p' "$FIXTURE/stderr.log" >&2
  exit 1
}

window_id="$(printf '%s\n' "$probe" | sed -n 's/^MATCHED_WINDOW_ID=//p' | head -1)"
[[ "$window_id" =~ ^[1-9][0-9]*$ ]] || { echo "status-surface: invalid window id" >&2; exit 1; }
screencapture -x -l "$window_id" "$CAPTURE"
[[ -s "$CAPTURE" ]] || { echo "status-surface: window capture missing" >&2; exit 1; }
shasum -a 256 "$CAPTURE"
echo "NATIVE_STATUS_SURFACE=PASS pid=$PID window=$window_id title=$TITLE"
