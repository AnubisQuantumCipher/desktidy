#!/bin/bash
# Contract: the independent validator accepts a coherent blocked summary and
# rejects duplicate IDs, zero-work summaries, a success claim with a required
# indeterminate lane, and missing originating exits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-full-local-release.py"
WORK="$(mktemp -d /private/tmp/desktidy-final-validator.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

cat >"$WORK/spec.json" <<'JSON'
{"schema":1,"gates":[{"id":"core","required":true},{"id":"visual","required":true}]}
JSON
cat >"$WORK/blocked.json" <<'JSON'
{"schema":1,"source_commit":"0123456789abcdef0123456789abcdef01234567","overall":"blocked","records":[{"id":"core","status":"passed","exit_code":0},{"id":"visual","status":"indeterminate","exit_code":0}]}
JSON
python3 "$VALIDATOR" --spec "$WORK/spec.json" --summary "$WORK/blocked.json"

cat >"$WORK/success-indeterminate.json" <<'JSON'
{"schema":1,"source_commit":"0123456789abcdef0123456789abcdef01234567","overall":"success","records":[{"id":"core","status":"passed","exit_code":0},{"id":"visual","status":"indeterminate","exit_code":0}]}
JSON
if python3 "$VALIDATOR" --spec "$WORK/spec.json" --summary "$WORK/success-indeterminate.json" >"$WORK/success.out" 2>&1; then
  echo "FAIL: validator accepted success with indeterminate required lane" >&2
  exit 1
fi
grep -Fq 'required lane visual is indeterminate' "$WORK/success.out"

cat >"$WORK/duplicate.json" <<'JSON'
{"schema":1,"source_commit":"0123456789abcdef0123456789abcdef01234567","overall":"blocked","records":[{"id":"core","status":"passed","exit_code":0},{"id":"core","status":"passed","exit_code":0}]}
JSON
if python3 "$VALIDATOR" --spec "$WORK/spec.json" --summary "$WORK/duplicate.json" >"$WORK/duplicate.out" 2>&1; then
  echo "FAIL: validator accepted duplicate gate ID" >&2
  exit 1
fi
grep -Fq 'duplicate gate ID' "$WORK/duplicate.out"

cat >"$WORK/missing-exit.json" <<'JSON'
{"schema":1,"source_commit":"0123456789abcdef0123456789abcdef01234567","overall":"blocked","records":[{"id":"core","status":"passed"},{"id":"visual","status":"indeterminate","exit_code":0}]}
JSON
if python3 "$VALIDATOR" --spec "$WORK/spec.json" --summary "$WORK/missing-exit.json" >"$WORK/missing-exit.out" 2>&1; then
  echo "FAIL: validator accepted missing originating exit" >&2
  exit 1
fi
grep -Fq 'missing originating exit' "$WORK/missing-exit.out"

cat >"$WORK/zero.json" <<'JSON'
{"schema":1,"source_commit":"0123456789abcdef0123456789abcdef01234567","overall":"success","records":[]}
JSON
if python3 "$VALIDATOR" --spec "$WORK/spec.json" --summary "$WORK/zero.json" >"$WORK/zero.out" 2>&1; then
  echo "FAIL: validator accepted zero-work summary" >&2
  exit 1
fi
grep -Fq 'zero-work summary' "$WORK/zero.out"

echo 'full-local-release-validator: PASS'
