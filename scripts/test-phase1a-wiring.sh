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

fail_if "$ROOT/src/Phase1A1Tests.swift" 'ProductionSMAdapter|SMAppService' \
  "phase1a1 tests mention production ServiceManagement mutator"

fail_if "$ROOT/src/Phase1BTests.swift" 'ProductionSMAdapter|SMAppService' \
  "phase1b tests mention production ServiceManagement mutator"

# Default path must still stop. The --commit-mutation branch is Phase 1B only.
if ! grep -q 'STOP_BEFORE_PRODUCTION_ADAPTER' "$ROOT/probe/ProbeMain.swift"; then
  echo "FAIL: probe lost the default stop-before-adapter boundary" >&2
  exit 1
fi
if ! grep -q 'if !args.contains("--commit-mutation")' "$ROOT/probe/ProbeMain.swift"; then
  echo "FAIL: probe lost the --commit-mutation gate" >&2
  exit 1
fi
# Public-boundary suite must never pair a valid grant with --commit-mutation.
if grep -nE -- '--commit-mutation' "$ROOT/scripts/test-phase1a1-public-boundary.sh" \
   | grep -E 'GOOD|good\.json|write_auth "\$GOOD"'; then
  echo "FAIL: public-boundary suite would invoke a granted mutation on CI" >&2
  exit 1
fi
if grep -nE 'observe-phase1b|commit-mutation' "$ROOT/.github/workflows/ci.yml"; then
  echo "FAIL: hosted CI must not run the Phase 1B observation path" >&2
  exit 1
fi

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
