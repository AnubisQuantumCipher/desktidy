# Changelog

## v1.2.0 — R0: single movement authority + canonical receipts

- **Authority guard:** DeskTidy now refuses to sort a folder that another
  launchd agent already watches (symlink-resolved, device/inode-compared
  roots; unknown/unreadable agents fail closed). `desktidy setup`,
  `install.sh`, and every engine start converge on the same guard.
  New: `desktidy-sort --authority-diagnose [--json]`.
- **Receipts:** every movement attempt now writes a durable, hash-chained
  receipt (prepare → move → complete, with deterministic crash reconciliation
  that reports `failed`/`recovered`/`indeterminate` — never invented success).
  New: `--history [n] [--json]`, `--verify-ledger`. Schema + state machine in
  docs/R0_AUTHORITY_AND_RECEIPTS.md.
- **Confinement:** symlink sources, symlinked destination dirs, `..`
  traversal, and out-of-root paths are rejected before any write; symlinks at
  the root are skipped (previously a symlinked file could be moved).
- **Verification:** 31 new hostile controls (`--r0-test`) run in CI alongside
  the existing 17-check self-test; an A→B→A tamper exercise confirmed the
  authority controls fail for the intended semantic reason when the guard is
  sabotaged.

## v1.0.0

First public release.

- Deterministic Desktop sorter (`desktidy-sort`): files loose items into
  Documents / Images / Screenshots / Videos / Audio / Archives / Code / Folders,
  with an Inbox fallback for anything it can't confidently place.
- Safety guarantees: never deletes; collision-safe moves (no overwrite);
  15s settle window; skips in-progress downloads; single-instance lock.
- Real-time notifications (`desktidy-notify.sh`): a macOS banner per move,
  **clickable** to reveal the file in Finder (via `terminal-notifier`, with a
  plain-banner fallback). Error banners break through Do Not Disturb.
- Optional on-device AI triage (macOS 26+ / Apple Intelligence): suggestions
  only, fully local; compiled out automatically on older macOS.
- `launchd` agents for hands-off operation that survives reboots.
- One-command `install.sh` / `uninstall.sh`. Retarget any folder with
  `--target`. Configure everything in `src/Config.swift`.

### Tested
- Deterministic routing, safety behaviors, and self-test: verified on
  macOS 26 (Apple Silicon), AI path included.
- The AI-excluded build path (`#if canImport(FoundationModels)`) is verified by
  CI on macOS 14 and macOS 15 runners: build, self-test, read-only probe,
  end-to-end sandbox sort, and collision safety all pass.
