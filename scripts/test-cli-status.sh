#!/bin/bash
# Isolated integration: public `desktidy status` must consume --effective-state
# and must not reconstruct target precedence in shell.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SORT_BIN="${1:-}"
if [ -z "$SORT_BIN" ] || [ ! -x "$SORT_BIN" ]; then
  echo "usage: $0 /path/to/desktidy-sort" >&2
  exit 2
fi

if grep -n 'PlistBuddy' "$ROOT/src/desktidy-cli.sh"; then
  echo "FAIL: desktidy-cli.sh still has a PlistBuddy target bypass" >&2
  exit 1
fi

PREFIX="$(mktemp -d /tmp/desktidy-status-prefix-XXXXXX)"
AG="$(mktemp -d /tmp/desktidy-status-ag-XXXXXX)"
TG_ENV="$(mktemp -d /tmp/desktidy-status-env-XXXXXX)"
TG_PLIST="$(mktemp -d /tmp/desktidy-status-plist-XXXXXX)"
TG_CFG="$(mktemp -d /tmp/desktidy-status-cfg-XXXXXX)"
AP="$(mktemp -d /tmp/desktidy-status-ap-XXXXXX)"

mkdir -p "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/share/desktidy"
cp "$ROOT/src/desktidy-cli.sh" "$PREFIX/bin/desktidy"
chmod +x "$PREFIX/bin/desktidy"
cp "$SORT_BIN" "$PREFIX/bin/desktidy-sort"
chmod +x "$PREFIX/bin/desktidy-sort"
cp "$ROOT/src/desktidy-notify.sh" "$PREFIX/libexec/desktidy-notify.sh"
cp "$ROOT/launchagents/"*.template "$PREFIX/share/desktidy/"

/usr/bin/python3 - "$AG" "$TG_PLIST" <<'PY'
import plistlib, sys, os, json
ag, tg = sys.argv[1], sys.argv[2]
prog = os.path.join(ag, "desktidy-sort")
open(prog, "w").write("#!/bin/sh\n")
with open(os.path.join(ag, "com.desktidy.sort.plist"), "wb") as f:
    plistlib.dump({
        "Label": "com.desktidy.sort",
        "ProgramArguments": [prog],
        "WatchPaths": [tg],
        "EnvironmentVariables": {"DESKTIDY_TARGET_DIR": tg},
    }, f)
with open(os.path.join(ag, "state.json"), "w") as f:
    json.dump({}, f)
PY
printf '%s\n' '{"schema":1,"target":"'"$TG_CFG"'"}' > "$AP/config.json"

export DESKTIDY_AGENTS_DIR="$AG"
export DESKTIDY_TARGET_DIR="$TG_ENV"
export DESKTIDY_APP_DIR="$AP"
export DESKTIDY_LAUNCHD_STATE_FILE="$AG/state.json"

JSON="$("$PREFIX/bin/desktidy-sort" --effective-state --json)"
STATUS="$("$PREFIX/bin/desktidy" status)"

echo "$JSON"
echo "$STATUS"

echo "$STATUS" | grep -F "target: $TG_CFG" >/dev/null
echo "$STATUS" | grep -F "overall: pausedNotLoaded" >/dev/null
if echo "$STATUS" | grep -F "$TG_PLIST" >/dev/null; then
  echo "FAIL: status echoed plist target instead of shared-state config target" >&2
  exit 1
fi
if echo "$STATUS" | grep -F "$TG_ENV" >/dev/null; then
  echo "FAIL: status echoed env target instead of shared-state config target" >&2
  exit 1
fi
echo "cli-status: PASS (shared effective-state target, no PlistBuddy)"
