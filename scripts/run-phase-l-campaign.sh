#!/bin/bash
# Run the compiled Phase L campaign against fresh /private/tmp evidence only.
set -euo pipefail

BINARY="${1:-}"
if [ -z "$BINARY" ] || [ ! -x "$BINARY" ]; then
  echo "usage: $0 /path/to/desktidy-sort" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(mktemp -d /private/tmp/desktidy-phase-l-run.XXXXXX)"
OUTPUT="$WORKDIR/campaign.jsonl"
SUMMARY="$WORKDIR/summary.json"
trap 'rm -rf "$WORKDIR"' EXIT

"$BINARY" --phasel-campaign --phase-l-output "$OUTPUT"
/usr/bin/python3 "$SCRIPT_DIR/phase-l-summarize.py" "$OUTPUT" > "$SUMMARY"
/usr/bin/python3 "$SCRIPT_DIR/phase-l-adjudicate.py" "$OUTPUT"
cat "$SUMMARY"
