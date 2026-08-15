# DeskTidy

DeskTidy is a local-native macOS file-organization project. Its current tree
contains an **ad-hoc local release candidate**, not a public release.

## Current status — 2026-08-15

- A local arm64 macOS 14+ RC was built, packaged, and verified on an isolated
  fixture. The package is ad-hoc signed; Gatekeeper assessed it as rejected.
  It is **not** Developer ID signed, notarized, publicly distributed, or a
  Homebrew release.
- The current public Homebrew formula, if any, predates this work. Do not use
  it as evidence for this RC and do not treat it as an installer for this tree.
- The RC was verified only against non-Desktop fixture paths. It has not been
  authorized to register a live service, alter a personal mover, or organize a
  real Desktop.
- The signed app now carries an inert migration bundle: the exact sorter,
  notifier, launch templates, source identity, hash manifest, and a
  transactional `migrate-live.sh`. Its default is plan-only. Fake-substrate
  gates prove ordered handoff and automatic rollback; no live cutover has been
  executed by this source checkpoint.
- The shared native status surface now has fixture-bound pixels, AX controls,
  and a required launch/capture gate. Keyboard focus traversal and spoken
  VoiceOver output remain **INDETERMINATE**, so this is not a complete native
  accessibility pass.
- Historical sacrificial `SMAppService` observations do not establish
  production migration, Login Items, FDA/TCC, reboot, or login behavior.

Evidence: [`docs/evidence/R2_PHASE_N_VISUAL_ACCESSIBILITY.md`](docs/evidence/R2_PHASE_N_VISUAL_ACCESSIBILITY.md),
[`docs/evidence/R2_OMP_PHASEA_INDEPENDENT_AUDIT.md`](docs/evidence/R2_OMP_PHASEA_INDEPENDENT_AUDIT.md), and
[`docs/evidence/R2_OMP_CONTINUATION_REQUIRED.md`](docs/evidence/R2_OMP_CONTINUATION_REQUIRED.md).

## Build and verify a local RC

Requirements: macOS 14+, Apple Silicon, Xcode command-line tools, and a clean
source tree. The commands below use temporary paths and do not install,
register, launch against the Desktop, or request permissions.

```bash
scripts/build-app.sh /private/tmp/desktidy-build/DeskTidy.app
scripts/package-local-rc.sh /private/tmp/desktidy-build/DeskTidy.app /private/tmp/desktidy-dist
scripts/verify-local-rc.sh \
  /private/tmp/desktidy-dist/DeskTidy-local-rc-arm64-macos14.zip \
  /private/tmp/desktidy-dist/DeskTidy-local-rc-manifest.json
```

`verify-local-rc.sh` checks the archive manifest, rejects unsafe archive paths
and symlinks before extraction, performs a fixture smoke, and records the
ad-hoc-signing/Gatekeeper boundary. It is local evidence only.

## Product safety model

The local RC's guarded movement core is tested on disposable fixture roots:

- one canonical movement authority; foreign, ambiguous, or invalid authority
  state refuses movement;
- deterministic routes and collision-safe names; no overwrite path;
- append-only receipt records with SHA-256 chaining, crash reconciliation, and
  bounded history/Undo queries;
- receipt-derived notifications, collision-safe Undo, and bounded App Intents
  are local-RC source capabilities with hermetic contracts, not a claim of
  live macOS service integration;
- suggestion outputs are non-mutating. They never authorize an automatic move.

The receipt chain is **unkeyed integrity evidence**, not authentication.

## Explicit non-claims

This repository does not currently provide a public installer, public release,
Homebrew update, notarization, Developer ID signing, live service registration,
Login Items confirmation, FDA/TCC confirmation, reboot/login proof, a complete
keyboard/VoiceOver accessibility pass, or a verified no-network binary audit. Optional
future update checks are absent from this RC.

## Repository map

- [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) — requirements and release
  gates; not a completed-release declaration.
- [`docs/R0_AUTHORITY_AND_RECEIPTS.md`](docs/R0_AUTHORITY_AND_RECEIPTS.md) —
  movement authority and receipts design.
- [`docs/ML_AUTHORITY_POLICY.md`](docs/ML_AUTHORITY_POLICY.md) — strict
  suggestion/action boundary.
- [`docs/evidence/`](docs/evidence/) — bounded observations and their limits.
- [`website/`](website/) — website source only. This phase does not deploy it.
- [`scripts/claims-scan.py`](scripts/claims-scan.py) — inventories configured
  active and excluded documentation surfaces; its contract and mutation control
  are in `scripts/test-claims-scan.sh`.

## Security reports

See [`SECURITY.md`](SECURITY.md). It describes the repository boundary and
reporting route; it does not assert a supported public release.
