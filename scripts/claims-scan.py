#!/usr/bin/env python3
"""Inventory release claims in active and historical DeskTidy documentation."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA = 1
DEFAULT_FILES = (
    "README.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "docs/RELEASE_PLAN.md",
    "docs/R1B_SERVICE_IDENTITY_PROPOSAL.md",
    "docs/R1B_PHASE1B_OPERATOR_RUNBOOK.md",
    "src/desktidy-cli.sh",
    "skills/AGENTS-SNIPPET.md",
    "skills/desktidy-awareness/SKILL.md",
    "website/app/page.tsx",
    "website/app/components/Faq.tsx",
    "website/WEBSITE_VERIFICATION.md",
    "website/BUSINESS_POSITIONING.md",
)
EXCLUDED_FILES = ("docs/evidence",)
RULES = (
    ("public-install", r"(?i)\bpublicly installable today\b"),
    ("homebrew-primary", r"(?i)\binstall with homebrew\b|\bhomebrew \(recommended\)\b"),
    ("verified-reboot", r"(?i)\bdoes it survive a reboot\?\s*yes\b|\breboot, shut down, come back\b"),
    ("absolute-login", r"(?i)\bstarts automatically at every login\b"),
    ("public-trust-stamp", r"(?i)\bproduction-grade\b|\bindustry[- ]ready\b|\bfully proven\b"),
)


def fail(message: str) -> None:
    raise SystemExit(f"claims-scan: {message}")


def relative_file(root: Path, value: str) -> Path:
    candidate = (root / value).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        fail(f"unsafe input path: {value}")
    if not candidate.is_file():
        fail(f"required input file missing: {value}")
    return candidate


def classified(relative: str) -> str:
    return "excluded" if any(relative == prefix or relative.startswith(prefix + "/") for prefix in EXCLUDED_FILES) else "active"


def scan(root: Path, names: list[str]) -> dict[str, Any]:
    records: list[dict[str, Any]] = []
    active_matches: list[dict[str, Any]] = []
    excluded_matches: list[dict[str, Any]] = []
    compiled = [(name, re.compile(pattern)) for name, pattern in RULES]

    for name in names:
        path = relative_file(root, name)
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        classification = classified(relative)
        records.append(
            {
                "path": relative,
                "classification": classification,
                "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                "bytes": len(text.encode("utf-8")),
            }
        )
        for line_number, line in enumerate(text.splitlines(), start=1):
            for rule_name, pattern in compiled:
                for match in pattern.finditer(line):
                    item = {
                        "path": relative,
                        "line": line_number,
                        "rule": rule_name,
                        "match": match.group(0),
                    }
                    (excluded_matches if classification == "excluded" else active_matches).append(item)

    summary: dict[str, Any] = {
        "schema": SCHEMA,
        "scanned_files": records,
        "rule_count": len(RULES),
        "active_matches": active_matches,
        "excluded_matches": excluded_matches,
        "active_match_count": len(active_matches),
        "excluded_match_count": len(excluded_matches),
        "violations": active_matches,
    }
    return summary


def validate_summary(summary: Any) -> None:
    if not isinstance(summary, dict) or summary.get("schema") != SCHEMA:
        fail("malformed summary")
    files = summary.get("scanned_files")
    rules = summary.get("rule_count")
    active = summary.get("active_matches")
    excluded = summary.get("excluded_matches")
    violations = summary.get("violations")
    if not isinstance(files, list) or not isinstance(rules, int) or not isinstance(active, list) or not isinstance(excluded, list) or not isinstance(violations, list):
        fail("malformed summary")
    if not files or rules <= 0:
        fail("zero-work summary")
    if summary.get("active_match_count") != len(active) or summary.get("excluded_match_count") != len(excluded):
        fail("malformed summary")
    if violations != active:
        fail("malformed summary")
    for record in files:
        if not isinstance(record, dict) or record.get("classification") not in {"active", "excluded"}:
            fail("malformed summary")
        if not isinstance(record.get("path"), str) or not isinstance(record.get("sha256"), str) or len(record["sha256"]) != 64:
            fail("malformed summary")
    for item in active + excluded:
        if not isinstance(item, dict) or not isinstance(item.get("path"), str) or not isinstance(item.get("line"), int) or not isinstance(item.get("rule"), str) or not isinstance(item.get("match"), str):
            fail("malformed summary")
    if active:
        fail("active claim violations present")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--files", nargs="+", help="relative files to scan instead of the canonical public surface")
    parser.add_argument("--output", type=Path, help="write JSON summary")
    parser.add_argument("--validate-summary", type=Path, help="validate a prior JSON summary")
    args = parser.parse_args()

    if args.validate_summary:
        if args.files or args.output:
            fail("--validate-summary cannot be combined with scan options")
        try:
            summary = json.loads(args.validate_summary.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            fail("malformed summary")
        validate_summary(summary)
        print("claims-scan: summary valid")
        return

    root = args.root.resolve()
    if not root.is_dir():
        fail("root is not a directory")
    if args.files:
        names = args.files
    else:
        names = list(DEFAULT_FILES)
        for excluded_directory in EXCLUDED_FILES:
            directory = root / excluded_directory
            if not directory.is_dir():
                fail(f"required excluded inventory directory missing: {excluded_directory}")
            names.extend(
                sorted(path.relative_to(root).as_posix() for path in directory.rglob("*.md"))
            )
    if not names:
        fail("zero-work scan")
    summary = scan(root, names)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "claims-scan: "
        f"{len(summary['scanned_files'])} files, {summary['rule_count']} rules, "
        f"{summary['active_match_count']} active matches, {summary['excluded_match_count']} excluded matches"
    )
    if summary["violations"]:
        for item in summary["violations"]:
            print(f"claims-scan: violation {item['path']}:{item['line']} [{item['rule']}] {item['match']}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
