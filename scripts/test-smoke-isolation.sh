#!/bin/bash
# Negative control: the smoke harness must refuse missing fixture isolation
# rather than probing the live machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SMOKE="$ROOT/scripts/smoke-app.sh"
chmod +x "$SMOKE" "$ROOT/scripts/test-cli-status.sh"

# Clear any inherited fixture vars from a parent test process.
unset DESKTIDY_AGENTS_DIR DESKTIDY_TARGET_DIR DESKTIDY_APP_DIR
unset DESKTIDY_LAUNCHD_STATE_FILE EXPECTED_OVERALL DESKTIDY_APP_BIN

set +e
OUT="$("$SMOKE" /usr/bin/true 2>&1)"
CODE=$?
set -e
echo "$OUT"
if [ "$CODE" -eq 0 ]; then
  echo "FAIL: smoke succeeded without fixture isolation" >&2
  exit 1
fi
echo "$OUT" | grep -q 'missing required fixture' || {
  echo "FAIL: smoke did not report missing fixture isolation" >&2
  exit 1
}
echo "smoke-isolation: PASS (exit $CODE)"
