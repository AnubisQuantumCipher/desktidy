#!/bin/bash
# Contract: a dry run emits a complete, internally valid blocked summary without
# executing commands or upgrading visual/hosted/lifecycle prerequisites to pass.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/scripts/run-full-local-release-gate.py"
VALIDATOR="$ROOT/scripts/validate-full-local-release.py"
SPEC="$ROOT/scripts/full-local-release-gates.json"
WORK="$(mktemp -d /private/tmp/desktidy-final-gate-test.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SUMMARY="$WORK/summary.json"
python3 "$RUNNER" --root "$ROOT" --output "$SUMMARY" --dry-run
python3 "$VALIDATOR" --spec "$SPEC" --summary "$SUMMARY"
python3 - "$SUMMARY" <<'PY'
import json
import sys
summary = json.load(open(sys.argv[1], encoding="utf-8"))
records = {record["id"]: record for record in summary["records"]}
assert summary["overall"] == "blocked"
assert len(records) == len(summary["records"])
assert records["visual-accessibility"]["status"] == "indeterminate"
assert records["hosted-final-sha"]["status"] == "blocked"
assert records["sacrificial-lifecycle"]["status"] == "blocked"
PY

echo 'full-local-release-gate: PASS'
