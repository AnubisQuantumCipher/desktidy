# DeskTidy

DeskTidy is a local-native macOS file organizer with one guarded movement
authority, durable receipts, and exact Undo. This repository currently supports
an **ad-hoc local deployment** on the operator Mac; it is not a public release.

## Current status — 2026-08-15

- The attainable deployment claim is **local production deployment operational
  and rollback-backed**. `com.desktidy.sort` and `com.desktidy.notify` are the
  installed services for `/Users/sicarii/Desktop`; live readback is
  `runningHealthy`, authority verdict `SOLE`, effective mover
  `com.desktidy.sort`, target source `nativeConfig`, and ledger `valid(8)`.
- The former `com.sicarii.desktop-autosort` and
  `com.sicarii.desktop-autosort-notify` services and active registration plists
  are absent. Their implementation and byte-verified rollback epoch are
  retained. Never load the former sorter while DeskTidy owns the Desktop.
- Migration persists native `config.json`, takes and verifies a bound backup of
  any prior DeskTidy support directory, tolerates missing unrelated WatchPaths,
  rejects same-target foreign or uninspectable authority, and uses
  process-exact quiescence checks. The fake-substrate transaction suite passes
  10 cases.
- The first live run exposed a compatibility defect that moved the retained
  `Archive`, `Docs`, `Media`, and `Projects` roots under `Folders/`. Those exact
  directories were restored with unchanged inodes. A shared compatibility set
  now protects all four in automatic and manual sweeps.
- The authorized PDF canary completed an actual
  `CanonicalApplicationCore.live().undo(receiptID:)` A→B→A cycle with identical
  SHA-256 and inode. Its first Undo exposed an immediate automatic re-sort;
  DeskTidy now serializes app and watcher movement through one process lock and
  automatically preserves the exact latest Undo restoration. The repaired
  live watcher was observed skipping that restored artifact before the canary
  was removed.
- The installed app and local RC are arm64/macOS 14+, ad-hoc signed, and
  deep-signature verified. Exact-SHA hosted CI passes on macOS 14 and macOS 15.
  Gatekeeper rejection remains expected for this local-only artifact.
- Keyboard focus-ring traversal and spoken VoiceOver output remain
  **INDETERMINATE**. Developer ID signing, notarization, TestFlight, App Store,
  and a public installer/release remain **BLOCKED** on Apple Developer Program
  access. No reboot was performed merely to manufacture evidence.

Deployment evidence:
[`docs/evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md`](docs/evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md).
Historical visual and implementation evidence remains under
[`docs/evidence/`](docs/evidence/).

## Build and verify a local RC

Requirements: macOS 14+, Apple Silicon, Xcode command-line tools, and a clean
source tree. These commands build only under `/private/tmp`; they do not install
or register services.

```bash
scripts/build-app.sh /private/tmp/desktidy-build
scripts/package-local-rc.sh \
  /private/tmp/desktidy-build/DeskTidy.app \
  /private/tmp/desktidy-dist
scripts/verify-local-rc.sh \
  /private/tmp/desktidy-dist/DeskTidy-local-rc-arm64-macos14.zip \
  /private/tmp/desktidy-dist/DeskTidy-local-rc-manifest.json
```

`verify-local-rc.sh` checks the archive manifest, rejects unsafe archive paths
and symlinks before extraction, validates the icon and migration bundle,
verifies the ad-hoc signature, and performs a fresh fixture smoke. It is local
evidence only.

## Product safety model

- One canonical movement authority; foreign, ambiguous, invalid-target, or
  damaged-ledger state refuses movement.
- One cross-process movement lock serializes watcher, Tidy Now, and Undo
  transactions. It refuses symbolic links, non-regular objects, foreign-owned
  files, and hard-linked lock inodes before changing permissions or locking.
- Deterministic routes and collision-safe names; no overwrite path.
- Append-only receipt records with SHA-256 chaining, crash reconciliation, and
  bounded history/Undo queries. The chain is unkeyed integrity evidence, not
  authentication.
- Undo restores only the exact receipt-bound artifact into an empty original
  slot. Automatic sweeps preserve that exact restoration; explicit Tidy Now is
  the user-authorized override.
- `Archive`, `Docs`, `Media`, and `Projects` are migration compatibility roots
  and remain at the watched root.
- Receipt-derived notifications are best effort and never define movement
  truth. An unbundled caller skips native notification setup safely.
- Smart-triage suggestions are non-mutating and never authorize a move.

## Explicit non-claims

This repository does not provide a Developer ID-signed or notarized build,
public DMG, public installer, Homebrew update, TestFlight/App Store release,
complete keyboard/VoiceOver acceptance, or verified reboot/login persistence.
The local deployment does not imply public distribution readiness.

## Repository map

- [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) — implemented local boundary
  and remaining release gates.
- [`docs/R0_AUTHORITY_AND_RECEIPTS.md`](docs/R0_AUTHORITY_AND_RECEIPTS.md) —
  movement authority and receipt design.
- [`docs/ML_AUTHORITY_POLICY.md`](docs/ML_AUTHORITY_POLICY.md) — strict
  suggestion/action boundary.
- [`docs/evidence/`](docs/evidence/) — observations, scars, and claim limits.
- [`website/`](website/) — website source; no deployment is claimed.
- [`scripts/claims-scan.py`](scripts/claims-scan.py) — public-claim inventory
  and mutation control.

## Security reports

See [`SECURITY.md`](SECURITY.md). It describes the repository boundary and
reporting route; it does not assert a supported public release.
