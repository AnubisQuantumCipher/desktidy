#!/usr/bin/env python3
"""Validate a canonical DeskTidy full-local-release gate summary."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA = 1
STATUSES = {"passed", "failed", "blocked", "indeterminate", "skipped"}
COMMIT = re.compile(r"^[0-9a-f]{40}$")


def reject(message: str) -> None:
    raise SystemExit(f"full-local-release-validator: {message}")


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        reject(f"malformed JSON: {path}")


def gate_spec(value: Any) -> dict[str, bool]:
    if not isinstance(value, dict) or value.get("schema") != SCHEMA or not isinstance(value.get("gates"), list):
        reject("malformed specification")
    gates: dict[str, bool] = {}
    for gate in value["gates"]:
        if not isinstance(gate, dict) or not isinstance(gate.get("id"), str) or not isinstance(gate.get("required"), bool):
            reject("malformed specification")
        if gate["id"] in gates:
            reject(f"duplicate gate ID in specification: {gate['id']}")
        gates[gate["id"]] = gate["required"]
    if not gates:
        reject("zero-work specification")
    return gates


def validate(specification: dict[str, bool], summary: Any) -> str:
    if not isinstance(summary, dict) or summary.get("schema") != SCHEMA:
        reject("malformed summary")
    if not isinstance(summary.get("source_commit"), str) or not COMMIT.fullmatch(summary["source_commit"]):
        reject("malformed source commit")
    overall = summary.get("overall")
    records = summary.get("records")
    if overall not in {"success", "blocked", "failed"} or not isinstance(records, list):
        reject("malformed summary")
    if not records:
        reject("zero-work summary")

    actual: dict[str, dict[str, Any]] = {}
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            reject("malformed record")
        identifier = record["id"]
        if identifier in actual:
            reject(f"duplicate gate ID: {identifier}")
        if identifier not in specification:
            reject(f"unexpected gate ID: {identifier}")
        if record.get("status") not in STATUSES:
            reject(f"malformed status for {identifier}")
        if not isinstance(record.get("exit_code"), int):
            reject(f"missing originating exit for {identifier}")
        if record["status"] == "passed" and record["exit_code"] != 0:
            reject(f"passed gate {identifier} has nonzero originating exit")
        actual[identifier] = record

    missing = sorted(set(specification) - set(actual))
    if missing:
        reject("missing gate IDs: " + ", ".join(missing))

    nonpassing_required: list[tuple[str, str]] = []
    for identifier, required in specification.items():
        if not required:
            continue
        status = actual[identifier]["status"]
        if status == "skipped":
            reject(f"required lane {identifier} is skipped")
        if status != "passed":
            nonpassing_required.append((identifier, status))

    if overall == "success":
        for identifier, status in nonpassing_required:
            reject(f"required lane {identifier} is {status} but overall is success")
        if any(record["status"] != "passed" for record in actual.values()):
            reject("overall success contains non-passing optional lane")
    elif not nonpassing_required and all(record["status"] == "passed" for record in actual.values()):
        reject(f"overall {overall} contradicts all-passing records")

    return overall


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    args = parser.parse_args()
    specification = gate_spec(load(args.spec))
    overall = validate(specification, load(args.summary))
    print(f"full-local-release-validator: valid overall={overall} gates={len(specification)}")


if __name__ == "__main__":
    main()
