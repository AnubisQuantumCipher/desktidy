#!/usr/bin/env python3
"""Run the canonical non-live DeskTidy local-release gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA = 1
TMP_ROOT = Path("/private/tmp").resolve()


def fail(message: str) -> None:
    raise SystemExit(f"full-local-release-gate: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_under_tmp(path: Path) -> Path:
    resolved = path.resolve(strict=False)
    try:
        resolved.relative_to(TMP_ROOT)
    except ValueError:
        fail(f"output must remain below {TMP_ROOT}: {resolved}")
    return resolved


def git(root: Path, *arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(root), *arguments], text=True).strip()


def ensure_clean_source(root: Path) -> str:
    if subprocess.run(["git", "-C", str(root), "diff", "--quiet"]).returncode != 0:
        fail("source tree is dirty; commit the exact release source first")
    if subprocess.run(["git", "-C", str(root), "diff", "--cached", "--quiet"]).returncode != 0:
        fail("index is dirty; commit the exact release source first")
    return git(root, "rev-parse", "--verify", "HEAD^{commit}")


def record_static(identifier: str, status: str, message: str, command: list[str]) -> dict[str, Any]:
    return {
        "id": identifier,
        "status": status,
        "exit_code": 0,
        "command": command,
        "message": message,
    }


def run_command(
    identifier: str,
    command: list[str],
    root: Path,
    log_dir: Path,
    environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    completed = subprocess.run(
        command,
        cwd=root,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    log = log_dir / f"{identifier}.log"
    log.write_text(
        "$ " + " ".join(command) + "\n\n[stdout]\n" + completed.stdout + "\n[stderr]\n" + completed.stderr,
        encoding="utf-8",
    )
    return {
        "id": identifier,
        "status": "passed" if completed.returncode == 0 else "failed",
        "exit_code": completed.returncode,
        "command": command,
        "log": str(log),
        "log_sha256": sha256(log),
    }


def write_summary(path: Path, source_commit: str, records: list[dict[str, Any]], overall: str, work: Path, dry_run: bool) -> None:
    summary = {
        "schema": SCHEMA,
        "source_commit": source_commit,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "overall": overall,
        "dry_run": dry_run,
        "work_root": str(work),
        "records": records,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = args.root.resolve()
    output = require_under_tmp(args.output)
    if not root.is_dir() or not (root / "scripts/full-local-release-gates.json").is_file():
        fail("root does not contain the canonical gate specification")
    if output.exists():
        fail(f"refusing to overwrite existing summary: {output}")
    spec = json.loads((root / "scripts/full-local-release-gates.json").read_text(encoding="utf-8"))
    gate_ids = [gate["id"] for gate in spec["gates"]]
    if len(gate_ids) != len(set(gate_ids)) or not gate_ids:
        fail("invalid canonical gate specification")

    source_commit = git(root, "rev-parse", "--verify", "HEAD^{commit}")
    work = Path(tempfile.mkdtemp(prefix="desktidy-full-local-release-", dir=TMP_ROOT))
    logs = work / "logs"
    logs.mkdir()
    records: list[dict[str, Any]] = []

    if args.dry_run:
        for identifier in gate_ids:
            if identifier == "visual-accessibility":
                records.append(record_static(identifier, "indeterminate", "Direct surface pixels exist, but keyboard focus and VoiceOver output remain unobserved.", ["evidence", "docs/evidence/R2_PHASE_N_VISUAL_ACCESSIBILITY.md"]))
            elif identifier in {"sacrificial-lifecycle", "hosted-final-sha", "website-build"}:
                records.append(record_static(identifier, "blocked", "Prerequisite deliberately unavailable in dry run.", ["not-run", identifier]))
            else:
                records.append(record_static(identifier, "blocked", "Dry run; command was not executed.", ["not-run", identifier]))
        write_summary(output, source_commit, records, "blocked", work, True)
        print(f"full-local-release-gate: dry-run blocked summary: {output}")
        return

    source_commit = ensure_clean_source(root)
    fixture = work / "fixture"
    for name in ("target", "agents", "app-support"):
        (fixture / name).mkdir(parents=True)
    (fixture / "launchd-state.json").write_text("{}\n", encoding="utf-8")
    binary = work / "desktidy-sort"
    app = work / "DeskTidy.app"
    dist = work / "dist"
    archive = dist / "DeskTidy-local-rc-arm64-macos14.zip"
    manifest = dist / "DeskTidy-local-rc-manifest.json"
    phase_environment = os.environ.copy()
    phase_environment.update(
        {
            "DESKTIDY_TARGET_DIR": str(fixture / "target"),
            "DESKTIDY_AGENTS_DIR": str(fixture / "agents"),
            "DESKTIDY_APP_DIR": str(fixture / "app-support"),
            "DESKTIDY_LAUNCHD_STATE_FILE": str(fixture / "launchd-state.json"),
        }
    )

    swift_sources = sorted(str(path) for path in (root / "src").glob("*.swift"))
    records.append(run_command("cli-compile", ["xcrun", "swiftc", "-O", "-parse-as-library", *swift_sources, "-o", str(binary)], root, logs, phase_environment))
    if records[-1]["status"] == "passed":
        records.append(run_command("cli-ad-hoc-sign", ["codesign", "-s", "-", "-i", "com.desktidy.sort", "--force", str(binary)], root, logs, phase_environment))
    else:
        records.append(record_static("cli-ad-hoc-sign", "blocked", "Compile failed; signing was not attempted.", ["codesign", "-s", "-", str(binary)]))

    binary_commands = {
        "legacy-self-test": [str(binary), "--self-test"],
        "legacy-health": [str(binary), "--health"],
        "fixture-access": [str(binary), "--check-access"],
        "r0-controls": [str(binary), "--r0-test"],
        "r1a-state": [str(binary), "--state-test"],
        "phase1a-fake": [str(binary), "--phase1a-test"],
        "phase1a1-nonce": [str(binary), "--phase1a1-test"],
        "phase1b-fake": [str(binary), "--phase1b-test"],
        "phase2-identity": [str(binary), "--phase2-test"],
        "phasec-core": [str(binary), "--phasec-test"],
        "phased-config": [str(binary), "--phased-test"],
        "phasee-pause": [str(binary), "--phasee-test"],
        "phasef-notifications": [str(binary), "--phasef-test"],
        "phaseg-undo": [str(binary), "--phaseg-test"],
        "phaseh-history": [str(binary), "--phaseh-test"],
        "phasei-intents": [str(binary), "--phasei-test"],
        "phasej-lifecycle": [str(binary), "--phasej-test"],
        "phasek-suggestions": [str(binary), "--phasek-test"],
        "phasel-contracts": [str(binary), "--phasel-test"],
    }
    for identifier, command in binary_commands.items():
        if records[0]["status"] == "passed":
            records.append(run_command(identifier, command, root, logs, phase_environment))
        else:
            records.append(record_static(identifier, "blocked", "CLI compile failed; command was not attempted.", command))

    script_commands = {
        "phase1a-wiring": ["scripts/test-phase1a-wiring.sh"],
        "phase1a1-public-boundary": ["scripts/test-phase1a1-public-boundary.sh"],
        "phase1b-retirement": ["scripts/test-phase1b-retirement.sh"],
        "sacrificial-probe-build": ["scripts/build-probe.sh", str(work / "probe")],
        "phasel-campaign": ["scripts/run-phase-l-campaign.sh", str(binary)],
        "archive-symlink-control": ["scripts/test-local-rc-packaging.sh"],
        "lifecycle-install-plan": ["scripts/plan-local-rc-lifecycle.sh", "--plan", "install", str(work / "lifecycle/DeskTidy.app")],
        "lifecycle-upgrade-plan": ["scripts/plan-local-rc-lifecycle.sh", "--plan", "upgrade", str(work / "lifecycle/DeskTidy.app")],
        "lifecycle-uninstall-plan": ["scripts/plan-local-rc-lifecycle.sh", "--plan", "uninstall", str(work / "lifecycle/DeskTidy.app")],
        "cli-status": ["scripts/test-cli-status.sh", str(binary)],
        "smoke-isolation": ["scripts/test-smoke-isolation.sh"],
        "live-migration-transaction": ["scripts/test-live-migration.sh"],
        "claims-mutation-control": ["scripts/test-claims-scan.sh"],
    }
    for identifier, command in script_commands.items():
        needs_binary = identifier in {"phasel-campaign", "cli-status"}
        if needs_binary and records[0]["status"] != "passed":
            records.append(record_static(identifier, "blocked", "CLI compile failed; command was not attempted.", command))
        else:
            records.append(run_command(identifier, command, root, logs, phase_environment))

    records.append(run_command("app-build", ["scripts/build-app.sh", str(work)], root, logs, phase_environment))
    app_build = records[-1]
    if app_build["status"] == "passed":
        records.append(run_command(
            "native-status-surface",
            ["scripts/test-native-status-surface.sh", str(app), str(work / "visual-accessibility.png")],
            root,
            logs,
            phase_environment,
        ))
    else:
        records.append(record_static(
            "native-status-surface",
            "blocked",
            "App build failed; native status surface was not launched.",
            ["scripts/test-native-status-surface.sh", str(app)],
        ))
    if app_build["status"] == "passed":
        records.append(run_command("local-rc-package", ["scripts/package-local-rc.sh", str(app), str(dist)], root, logs, phase_environment))
    else:
        records.append(record_static("local-rc-package", "blocked", "App build failed; packaging was not attempted.", ["scripts/package-local-rc.sh", str(app), str(dist)]))
    package_record = records[-1]
    if package_record["status"] == "passed":
        records.append(run_command("local-rc-verify", ["scripts/verify-local-rc.sh", str(archive), str(manifest)], root, logs, phase_environment))
    else:
        records.append(record_static("local-rc-verify", "blocked", "Packaging failed; verification was not attempted.", ["scripts/verify-local-rc.sh", str(archive), str(manifest)]))

    claims_summary = work / "claims-summary.json"
    records.append(run_command("claims-summary", ["python3", "scripts/claims-scan.py", "--root", str(root), "--output", str(claims_summary)], root, logs, phase_environment))
    shell_scripts = sorted(str(path.relative_to(root)) for path in (root / "scripts").glob("*.sh"))
    records.append(run_command("shell-syntax", ["bash", "-n", "src/desktidy-cli.sh", *shell_scripts], root, logs, phase_environment))

    evidence = root / "docs/evidence/R2_OMP_PHASEA_INDEPENDENT_AUDIT.md"
    records.append(record_static("phase1b-evidence", "indeterminate", "Independent audit retains the historical lifecycle record as non-reproducible evidence.", ["evidence", str(evidence)]))
    records.append(record_static("visual-accessibility", "indeterminate", "Direct surface pixels and AX controls were observed, but keyboard focus and VoiceOver output remain unobserved.", ["evidence", "docs/evidence/R2_PHASE_N_VISUAL_ACCESSIBILITY.md"]))
    records.append(record_static("sacrificial-lifecycle", "blocked", "No direct install/upgrade/uninstall occurred; only plan-only lifecycle controls were run.", ["not-run", "direct local lifecycle"] ))

    uid = str(os.getuid())
    live_command = (
        f"launchctl print gui/{uid}/com.desktidy.sort >/dev/null && "
        f"launchctl print gui/{uid}/com.desktidy.notify >/dev/null && "
        f"! launchctl print gui/{uid}/com.sicarii.desktop-autosort >/dev/null 2>&1 && "
        f"! launchctl print gui/{uid}/com.sicarii.desktop-autosort-notify >/dev/null 2>&1 && "
        "/usr/libexec/PlistBuddy -c 'Print :WatchPaths:0' "
        "\"$HOME/Library/LaunchAgents/com.desktidy.sort.plist\" | "
        "grep -Fx \"$HOME/Desktop\""
    )
    live = run_command("live-authority-readback", ["/bin/bash", "-c", live_command], root, logs, phase_environment)
    live["message"] = (
        "Read-only checks require both DeskTidy labels, both legacy labels absent, "
        "and the sorter target equal to the operator Desktop."
    )
    records.append(live)
    records.append(run_command(
        "website-build",
        ["/bin/bash", "-c", "npm --prefix website ci --ignore-scripts && npm --prefix website run lint && npm --prefix website run build && npm --prefix website audit --audit-level=high"],
        root,
        logs,
        phase_environment,
    ))
    records.append(record_static("hosted-final-sha", "blocked", "No hosted macOS 14/15 CI run is tied to this local source commit.", ["not-run", "hosted CI"]))

    by_id = {record["id"]: record for record in records}
    if set(by_id) != set(gate_ids) or len(by_id) != len(records):
        fail("runner/spec gate ID mismatch")
    overall = "success" if all(record["status"] == "passed" for record in records) else "failed" if any(record["status"] == "failed" for record in records) else "blocked"
    write_summary(output, source_commit, records, overall, work, False)
    print(f"full-local-release-gate: overall={overall} summary={output} work={work}")
    raise SystemExit(0 if overall == "success" else 2)


if __name__ == "__main__":
    main()
