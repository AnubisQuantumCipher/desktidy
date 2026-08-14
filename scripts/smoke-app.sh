#!/bin/bash
# Hermetic headless smoke of the menu-bar binary. Requires isolated fixtures.
# Never probes the live Desktop or live launchd.
set -euo pipefail

need() {
  local n="$1"
  if [ -z "${!n:-}" ]; then
    echo "smoke: missing required fixture variable $n" >&2
    exit 2
  fi
}

need DESKTIDY_AGENTS_DIR
need DESKTIDY_TARGET_DIR
need DESKTIDY_APP_DIR
need DESKTIDY_LAUNCHD_STATE_FILE
need EXPECTED_OVERALL

APP_BIN="${1:-${DESKTIDY_APP_BIN:-}}"
if [ -z "$APP_BIN" ] || [ ! -x "$APP_BIN" ]; then
  echo "smoke: app binary required as \$1 or DESKTIDY_APP_BIN" >&2
  exit 2
fi

[ -d "$DESKTIDY_AGENTS_DIR" ] || { echo "smoke: agents dir does not exist" >&2; exit 2; }
[ -d "$DESKTIDY_TARGET_DIR" ] || { echo "smoke: target dir does not exist" >&2; exit 2; }
[ -d "$DESKTIDY_APP_DIR" ] || { echo "smoke: app-support dir does not exist" >&2; exit 2; }
[ -f "$DESKTIDY_LAUNCHD_STATE_FILE" ] || { echo "smoke: launchd fixture file is absent" >&2; exit 2; }

/usr/bin/python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
  "$DESKTIDY_LAUNCHD_STATE_FILE" || {
  echo "smoke: launchd fixture is not valid JSON" >&2
  exit 2
}

OUT="$("$APP_BIN" --smoke)"
echo "$OUT"
last="$(printf '%s\n' "$OUT" | tail -1)"
expected="SMOKE overall=$EXPECTED_OVERALL"
if [ "$last" != "$expected" ]; then
  echo "smoke: expected $expected, got $last" >&2
  exit 1
fi
