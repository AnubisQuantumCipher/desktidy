#!/bin/bash
# Contract: scanner inventories configured active/excluded surfaces, validates its
# own summary, rejects an injected active public-release claim, and rejects a
# malformed or zero-work summary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCANNER="$ROOT/scripts/claims-scan.py"
WORK="$(mktemp -d /private/tmp/desktidy-claims-test.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

SUMMARY="$WORK/summary.json"
python3 "$SCANNER" --root "$ROOT" --output "$SUMMARY"
python3 "$SCANNER" --validate-summary "$SUMMARY"
if ! python3 -c 'import json, sys; assert any(item["classification"] == "excluded" for item in json.load(open(sys.argv[1], encoding="utf-8"))["scanned_files"])' "$SUMMARY"; then
  echo "FAIL: scanner did not inventory excluded evidence" >&2
  exit 1
fi


mkdir -p "$WORK/mutation"
printf '%s\n' 'DeskTidy is production-grade and publicly installable today.' > "$WORK/mutation/README.md"
if python3 "$SCANNER" --root "$WORK/mutation" --files README.md >"$WORK/mutation.out" 2>&1; then
  echo "FAIL: scanner accepted injected active public-release claim" >&2
  exit 1
fi
if ! grep -Fq 'production-grade' "$WORK/mutation.out"; then
  echo "FAIL: mutation failure did not identify the injected claim" >&2
  exit 1
fi

printf '%s\n' '{"schema":1,"scanned_files":[],"rule_count":0,"active_matches":[],"excluded_matches":[],"active_match_count":0,"excluded_match_count":0,"violations":[]}' > "$WORK/zero.json"
if python3 "$SCANNER" --validate-summary "$WORK/zero.json" >"$WORK/zero.out" 2>&1; then
  exit 1
fi
if ! grep -Fq 'zero-work' "$WORK/zero.out"; then
  echo "FAIL: zero-work rejection missing" >&2
  exit 1
fi

printf '%s\n' '{not json' > "$WORK/malformed.json"
if python3 "$SCANNER" --validate-summary "$WORK/malformed.json" >"$WORK/malformed.out" 2>&1; then
  echo "FAIL: scanner accepted malformed summary" >&2
  exit 1
fi
if ! grep -Fq 'malformed summary' "$WORK/malformed.out"; then
  echo "FAIL: malformed-summary rejection missing" >&2
  exit 1
fi

echo 'claims-scan: PASS'
