#!/bin/bash
# The historical Phase 1B lifecycle must never be replayable by this checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OBSERVE="$ROOT/scripts/observe-phase1b.sh"

python3 - "$OBSERVE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = 'echo "observe-phase1b: retired after recorded lifecycle; no replay is authorized" >&2\nexit 2\n'
try:
    marker_offset = text.index(marker)
    mutation_offset = text.index("--commit-mutation")
except ValueError as error:
    raise SystemExit(f"FAIL: Phase 1B retirement fuse missing: {error}")
if marker_offset >= mutation_offset:
    raise SystemExit("FAIL: Phase 1B retirement fuse is not before mutation syntax")
PY

set +e
output="$("$OBSERVE" 2>&1)"
rc=$?
set -e
if [ "$rc" -ne 2 ] || [ "$output" != "observe-phase1b: retired after recorded lifecycle; no replay is authorized" ]; then
  echo "FAIL: retired observation invocation was not refused exactly (rc=$rc output=$output)" >&2
  exit 1
fi

echo "phase1b-retirement: PASS"
