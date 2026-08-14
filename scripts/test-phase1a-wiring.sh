#!/bin/bash
# Structural wiring: automated tests must not construct a production mutator.
# A planted poison in a temp copy must make this script fail.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail_if() {
  local path="$1" pat="$2" msg="$3"
  if sed 's://.*$::' "$path" | grep -nE "$pat"; then
    echo "FAIL: $msg ($path)" >&2
    exit 1
  fi
}

fail_if "$ROOT/src/Phase1ATests.swift" 'ProductionSMAdapter|SMAppService' \
  "test file mentions production ServiceManagement mutator"

fail_if "$ROOT/scripts/build-probe.sh" 'SMAppService\.register|launchctl (bootstrap|bootout|kickstart)' \
  "probe build script contains registration/launchd mutation"

if grep -nE '\|\| true' "$ROOT/scripts/build-probe.sh"; then
  echo "FAIL: probe build script masks failure" >&2
  exit 1
fi

fail_if "$ROOT/probe/HelperMain.swift" 'moveItem|copyItem|removeItem|URLSession|bootstrap|bootout' \
  "helper contains movement/network/launchd symbols"

# Negative control: plant a production adapter call and prove we detect it.
TMP=$(mktemp)
sed 's://.*$::' "$ROOT/src/Phase1ATests.swift" > "$TMP"
echo 'let _ = ProductionSMAdapter(); try SMAppService.agent(plistName: "x").register()' >> "$TMP"
if sed 's://.*$::' "$TMP" | grep -nE 'ProductionSMAdapter|SMAppService'; then
  echo "wiring-poison-control: detected planted production mutator"
else
  echo "FAIL: wiring poison control did not fire" >&2
  exit 1
fi
rm -f "$TMP"
echo "phase1a-wiring: PASS"
