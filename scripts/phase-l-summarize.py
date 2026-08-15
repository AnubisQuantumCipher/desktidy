#!/usr/bin/env python3
"""Independently recompute the finite Phase L campaign summary from JSONL."""

import json
import os
import sys

EXPECTED_SEED = 0x4C5F_2026_0814
EXPECTED_CASES = 14
TMP_ROOT = "/private/tmp/"


def fail(message: str) -> None:
    print(f"phase-l-summary: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_records(path: str) -> list[dict]:
    normalized = os.path.realpath(path)
    if not normalized.startswith(TMP_ROOT):
        fail("raw evidence must resolve beneath /private/tmp")
    try:
        with open(normalized, "r", encoding="utf-8") as evidence:
            lines = evidence.read().splitlines()
    except OSError as error:
        fail(f"cannot read raw evidence: {error}")
    if not lines:
        fail("raw evidence contains no records")
    records = []
    for line_number, line in enumerate(lines, start=1):
        if not line:
            fail(f"empty JSONL record at line {line_number}")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            fail(f"invalid JSON at line {line_number}: {error.msg}")
        if not isinstance(record, dict):
            fail(f"record at line {line_number} is not an object")
        records.append(record)
    return records


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: phase-l-summarize.py /private/tmp/<campaign>.jsonl")
    records = read_records(sys.argv[1])
    ids = [record.get("id") for record in records]
    statuses = [record.get("status") for record in records]
    checks = [record.get("checks") for record in records]
    summary = {
        "caseCount": len(records),
        "failedCases": statuses.count("failed"),
        "fixedSeed": EXPECTED_SEED,
        "idsUnique": len(ids) == len(set(ids)) and all(isinstance(value, str) and value for value in ids),
        "nonzeroChecks": all(isinstance(value, int) and not isinstance(value, bool) and value > 0 for value in checks),
        "passedCases": statuses.count("passed"),
        "seedMatches": all(record.get("seed") == EXPECTED_SEED for record in records),
        "timedOutCases": statuses.count("timedOut"),
        "totalMatchesExpected": len(records) == EXPECTED_CASES,
        "unknownStatusCases": sum(status not in {"passed", "failed", "timedOut"} for status in statuses),
    }
    summary["admissible"] = (
        summary["totalMatchesExpected"]
        and summary["seedMatches"]
        and summary["idsUnique"]
        and summary["nonzeroChecks"]
        and summary["passedCases"] == EXPECTED_CASES
        and summary["failedCases"] == 0
        and summary["timedOutCases"] == 0
        and summary["unknownStatusCases"] == 0
    )
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))
    return 0 if summary["admissible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
