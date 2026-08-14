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

if ! grep -q 'if !args.contains("--commit-mutation")' "$ROOT/probe/ProbeMain.swift"; then
  echo "FAIL: probe missing --commit-mutation stop before production adapter" >&2
  exit 1
fi
# Unsealed/early construction: ProductionSMAdapter must not appear before GRANT_PREPARED.
PROBE_SRC="$(sed 's://.*$::' "$ROOT/probe/ProbeMain.swift")"
BEFORE="${PROBE_SRC%%GRANT_PREPARED*}"
if printf '%s' "$BEFORE" | grep -nE 'ProductionSMAdapter\(|executeSealedRegister|executeSealedUnregister'; then
  echo "FAIL: probe constructs or invokes production mutator before GRANT_PREPARED" >&2
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

# Unsealed-call poison: ProductionSMAdapter before GRANT_PREPARED must fail.
POISON=$(mktemp)
sed 's://.*$::' "$ROOT/probe/ProbeMain.swift" > "$POISON"
python3 - "$POISON" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
needle = "print(\"GRANT_PREPARED\")"
if needle not in text:
    raise SystemExit("missing GRANT_PREPARED marker")
text = text.replace(needle, "let _ = ProductionSMAdapter()\n                        " + needle, 1)
p.write_text(text)
PY
POISON_SRC="$(sed 's://.*$::' "$POISON")"
POISON_BEFORE="${POISON_SRC%%GRANT_PREPARED*}"
if printf '%s' "$POISON_BEFORE" | grep -nE 'ProductionSMAdapter\('; then
  echo "wiring-unsealed-poison-control: detected early production adapter"
else
  echo "FAIL: unsealed-call poison control did not fire" >&2
  exit 1
fi
rm -f "$POISON"
echo "phase1a-wiring: PASS"
