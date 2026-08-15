# Changelog

## Unreleased — R2 local native RC (not a public release)

- The authorized local migration replaced the active personal Desktop sorter
  with `com.desktidy.sort` and `com.desktidy.notify`, persisted native config,
  removed old active registration plists, and retained byte-verified rollback
  assets. Direct state is `SOLE` / `runningHealthy`; this is a local deployment,
  not a public release.
- Migration transaction controls now cover 10 cases, including bound prior
  support backup/restore, missing unrelated WatchPaths, process-exact
  quiescence, old-plist removal, and rollback after partial shutdown.
- Routing policy v2 restores the exact five-root Desktop contract: `Archive`,
  `Docs`, `Inbox`, `Media`, and `Projects`. Documents, screenshots, other media,
  archives, code, and dropped folders route only beneath those roots. Nested
  receipt recovery/history paths retain traversal and symlink confinement.
- Watcher, Tidy Now, and Undo share one cross-process movement lock. Automatic
  sweeps preserve the exact latest durable Undo restoration; damaged-ledger
  startup fails closed. The named live canary completed a stable actual-core
  A→B→A cycle and was removed only after its evidence was recorded.
- The movement lock now opens no-follow, verifies a current-user-owned regular
  single-link inode, and has a hostile symbolic-link regression control.
- The inactive website waitlist/API and Neon dependency were removed; website
  and privacy copy now match the bounded local-deployment evidence.
- The installed arm64 macOS 14+ app remains ad-hoc signed. Gatekeeper rejection
  is expected. A source-built Homebrew developer preview exists; Developer ID
  signing, notarization, TestFlight/App Store, and a supported public production
  release remain absent.
- Direct pixels and AX controls exist, but keyboard focus traversal and spoken
  VoiceOver output remain **INDETERMINATE**. Historical sacrificial evidence
  does not prove Login Items, FDA/TCC, reboot, or login behavior.

## Unreleased (branch r1b/phase1b-sacrificial-observation — stacked on Phase 1A.1, non-final)

- **R1B Phase 1B (sacrificial observation path):** the sealed
  `PreparedMutationGrant` may be connected to exactly one
  `SMAppService.register` / `.unregister` call, and only after
  `--commit-mutation`. The default public probe path still exits 4 with a
  zero ledger. Ungranted overloads stay disconnected. Hosted CI does not
  run the observation. Production self-labels are unchanged. Ad-hoc
  signing remains development evidence only.
- **Local sacrificial observation (2026-08-14, commit `4725c51`):**
  register returned `success` / `status=enabled`; `launchctl print`
  showed `com.desktidy.sacrificial` submitted by ServiceManagement
  (`parent bundle identifier=com.desktidy.sacrificial-probe`, helper
  not running). Unregister returned `notRegistered` and print rc 113.
  Personal movers stayed loaded. Transcript:
  `docs/evidence/R1B_PHASE1B_SACRIFICIAL_OBSERVATION.md`. Login Items
  string, FDA/TCC, and reboot/login were not observed.

## Unreleased (branch r1b/phase1a-smappservice-harness — stacked on Phase 0, non-final)

- **R1B Phase 1A.1 (measured evidence seal, still no live mutation):** the
  sacrificial probe builds `InterlockContext` from measured executable
  SHA-256, compiled 40-hex source commit, one-open authorization bytes,
  two root/authority observations, and a durable `O_CREAT|O_EXCL` nonce.
  A sealed `PreparedMutationGrant` is produced then the probe exits 4
  (`STOP_BEFORE_PRODUCTION_ADAPTER`) with a zero construction/call ledger.
  Production adapter methods exist but return fail-closed and do not call
  `SMAppService.register` / `.unregister`. Phase 1B still requires a
  reviewed connection patch plus separate architect authorization.
- **R1B Phase 1A (fake-substrate only):** sacrificial SMAppService harness —
  migration state machine, injectable fake adapter, multi-factor mutation
  interlock, simulated transaction/rollback matrix, non-production probe
  bundle (ad-hoc, development evidence). No real `SMAppService.register`
  or `.unregister` execution. Apple public distribution membership
  unresolved. Phase 1B observation is separately authorized.

## Unreleased (branch r1b/phase0-unified-truth — stacked on R1A, non-final)

- **R1B Phase 0 (no live service migration):** one target resolver, one
  app-support/receipt path helper, public `desktidy status` consumes
  `--effective-state`, requested-but-invalid launchd fixtures fail closed,
  product identity is centralized without widening the accepted self set.
  Native `config.json` is a reader/model only — nothing writes it yet.
  Schema-1 native config is parsed from raw UTF-8 with a strict object
  parser; duplicate keys (including escaped-equivalent spellings) fail
  closed and do not fall through.

## Unreleased (branch r1a/public-trust-surface)

- **Experimental menu-bar app (read-only trust surface):** build from source
  with `scripts/build-app.sh`. Shows watched folder, effective movement
  authority, agent state, and receipt-ledger health — derived from launchd
  evidence and ledger verification via the same `EffectiveState` model the CLI
  prints with `desktidy-sort --effective-state [--json]`. Conflict, ambiguity,
  and ledger damage always render fail-closed; a plist on disk is never
  treated as "running". Read-only actions only (reveal folder/receipts, copy
  diagnostic). Not packaged, not shipped.
- **Docs truth pass:** README no longer implies an Undo command exists, and
  the roadmap no longer proposes automatic model-authorized moves.

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

Historical changelog entry; not evidence of a current public release.

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
