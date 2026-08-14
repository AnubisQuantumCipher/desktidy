#!/usr/bin/env python3
"""Independently reject malformed or non-passing finite Phase L evidence."""
import json
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: phase-l-adjudicate.py /private/tmp/<campaign>.jsonl")

path = Path(sys.argv[1]).resolve()
sandbox = Path("/private/tmp").resolve()
try:
    path.relative_to(sandbox)
except ValueError:
    raise SystemExit("refusing evidence path outside /private/tmp")

records = []
with path.open(encoding="utf-8") as source:
    for line_number, line in enumerate(source, 1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"invalid JSONL at line {line_number}: {error.msg}")
        required = {"schema", "id", "seed", "caseIndex", "caseName", "status", "checks", "timeoutMilliseconds"}
        if set(record) - (required | {"detail"}) or not required <= set(record):
            raise SystemExit(f"invalid fields at line {line_number}")
        if record["schema"] != 1 or record["status"] != "passed" or record["checks"] <= 0:
            raise SystemExit(f"non-passing record at line {line_number}")
        records.append(record)

if len(records) != 14 or len({record["id"] for record in records}) != 14:
    raise SystemExit("expected exactly 14 unique finite campaign records")
if [record["caseIndex"] for record in records] != list(range(1, 15)):
    raise SystemExit("case indexes are not the exact fixed 1...14 campaign")

print("PHASE L ADJUDICATION: accepted 14 finite passing records; not universal proof")
