# R2 live-migration patch completion receipt

Date: 2026-08-15
Implementation checkpoint: `a544ae6c79ad492378db65dc11ef8601e80fe0ae`
Parent icon checkpoint: `47902564f6d294dd0bbbb0fab7b7989434f26f45`
Hosted run: https://github.com/AnubisQuantumCipher/desktidy/actions/runs/31870994714

## Implemented

- The signed `DeskTidy.app` now embeds `Contents/Resources/Migration/` with:
  - the exact warning-clean `desktidy-sort` binary;
  - DeskTidy's notifier consuming `desktidy.log`, not the personal sorter's log;
  - sorter and notifier launch-agent templates;
  - plan-first `migrate-live.sh`;
  - exact source identity and per-file SHA-256 manifest.
- `migrate-live.sh` defaults to `--plan`; execution requires an existing app,
  canonical non-symlink target, exact hash-valid rollback epoch, matching live
  legacy plists, absent prior DeskTidy service installation, and an unambiguous
  launch-agent watcher inventory.
- The handoff order is old notifier → old sorter → new sorter → new notifier.
  The new sorter never starts while the old sorter is loaded.
- Any post-quiescence failure arms automatic rollback. Rollback removes any new
  labels, restores exact old files, and restores only old labels that are not
  already loaded.
- Old sorter files are retained; this is authority transfer, not uninstall-first.

## TDD scars retained

1. Missing migration command: RED exit 127.
2. Unimplemented execute path: RED exit 2.
3. Prior DeskTidy installation false accept: RED (`rc=0`) before refusal.
4. Unexpected same-root foreign authority false accept: RED (`rc=0`) before
   launch-agent inventory enforcement.
5. Partial old shutdown produced rollback failure (`rc=3`) before rollback
   learned to preserve an already-loaded old sorter.
6. The first package GREEN caught an invalid handwritten 40-hex cardinality
   check; both producer-facing validators now use exact regex syntax.

## Executed evidence at implementation checkpoint

Focused:

- `LIVE_MIGRATION_TEST=PASS cases=7`.
- `PHASE2 GATES: 16 passed, 0 failed`.
- All Swift sources compiled with `-warnings-as-errors`.
- Claims scanner: 25 files, 5 rules, 0 active or excluded matches.
- Shell/Python/JSON syntax and `git diff --check`: PASS.

Canonical local and fresh public clone:

- 46 records;
- 40 passed;
- 0 failed;
- 3 indeterminate;
- 3 blocked;
- `live-migration-transaction`: passed;
- app build, native status surface, RC package, and independent RC verify: passed;
- independent canonical validator: valid.

Hosted exact-SHA CI:

- macOS 14: PASS;
- macOS 15: PASS;
- dedicated migration bundle + fake-substrate transaction step: PASS on both;
- native status surface: PASS on both;
- CodeRabbit: PASS.

## Artifact hashes

- Embedded migration `SHA256SUMS`:
  `b9599661d5d1d0f554c7fb0d072aad2fa2b1e014b8a8b1d9e0d5be408ef80cc3`
- Embedded `migrate-live.sh`:
  `a556b9bf81bc8432651e4705094dfded30bfc9f43c08bb5a0c77c00af6f3f837`
- Embedded `desktidy-sort`:
  `6bc5fcd5d72dfe9cb3d11b8a267fe1238b928eba4dde66e83e56046f828259fd`
- RC archive:
  `a7805c6737209e34f8b85e09c3563c882c456728e91267b495b6e79087a486b5`
- RC manifest:
  `1d2c3132250449ecef6e337fdf43858cb2f5e598653c86b1f9586575e8ca894c`
- Clean-clone canonical summary:
  `20a67c1308aa25cca9f7f3e155a8fadf13aaca25d5c464cd383ad6ea89fb0f9f`
- Hosted run JSON:
  `d81e047d17c28ab22161bf72bb91c587d7f1a85cd5e29906f35aa020557b7a27`

## Live-state boundary

Read back after all tests:

- loaded: `com.sicarii.desktop-autosort`;
- loaded: `com.sicarii.desktop-autosort-notify`;
- absent: `com.desktidy.sort`;
- absent: `com.desktidy.notify`;
- absent: `com.desktidy.sacrificial`.

The installed UI app remains source `47902564...`; the migration-capable RC was
verified from temporary clean-clone output and was not installed over it.

## Non-claims

- No live authority cutover was executed.
- No file on `/Users/sicarii/Desktop` was used as a migration test.
- Reboot/login persistence, Full Disk Access for the new sorter, notification
  delivery, and a live canary remain unobserved until an explicitly approved
  cutover.
- Developer ID signing, notarization, and public distribution remain blocked.
