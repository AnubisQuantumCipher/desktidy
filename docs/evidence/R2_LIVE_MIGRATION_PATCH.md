# R2 live migration and remediation receipt

Date: 2026-08-15

This document reconciles the original migration-patch evidence with the later
authorized local deployment. It preserves the failed-closed attempts and the
post-cutover defects; it does not rewrite the migration as a smooth event.

Historical migration-bundle checkpoint:
`a544ae6c79ad492378db65dc11ef8601e80fe0ae`

Successful transaction code lineage ended at starting deployment checkpoint:
`ff03c82436098899f9d82542303832994e06887a`

Undo/remediation code checkpoint:
`42baf3380751e110ad297498fbc25346c6879fef`

Native app refusal-presentation checkpoint:
`2874d05a9b2fb1a766e62297c23ec4ff7a42787d`

PR: <https://github.com/AnubisQuantumCipher/desktidy/pull/6>

## Final transaction behavior

The signed `DeskTidy.app` embeds `Contents/Resources/Migration/` with the exact
sorter, notifier, launch templates, plan-first migration script, source
identity, and per-file SHA-256 manifest.

Execution requires an existing app, canonical non-symlink target, exact
hash-valid rollback epoch, a bound backup for any existing DeskTidy support
directory, matching live prior-service plists, and an inspectable launch-agent
inventory. It rejects a same-target foreign mover and unreadable same-target
authority. A missing WatchPath unrelated to the target no longer creates a
false ambiguity.

The ordered handoff is prior notifier → prior sorter → DeskTidy sorter →
DeskTidy notifier. Quiescence uses process-exact matching and cannot match the
migration command itself. Any post-quiescence failure removes the new labels,
restores exact old files/plists, and restores only old labels that are not
already loaded.

After successful bootout, the two old active registration plists are removed
from `~/Library/LaunchAgents`. Byte-identical copies remain in the sealed
rollback epoch and the separate legacy registration archive. Old implementation
files remain retained; inactive rollback material is not a second authority.

Focused transaction gate:

```text
LIVE_MIGRATION_TEST=PASS cases=10
```

The ten cases cover plan-only, first install, missing required prior-support
binding, existing-support overlay and byte restore, same-target foreign
authority, missing unrelated WatchPath, notifier rollback, partial old-service
shutdown rollback, and process-exact quiescence.

## Live attempts and scars

1. Existing support directory refusal:
   `/private/tmp/desktidy-live-cutover-c58fdea.log`

   SHA-256:
   `36f1f320af1b121618ec4c6a659f4970a3bea68b75f4e46145a8769202f26755`
2. Missing unrelated WatchPath ambiguity:
   `/private/tmp/desktidy-live-cutover-7c9a5c0.log`

   SHA-256:
   `9f0d366e0dabbfc0ab6992670df0414db0bdd2743fda266acc63abd3decdc0e4`
3. Process self-match quiescence refusal:
   `/private/tmp/desktidy-live-cutover-5854e86.log`

   SHA-256:
   `47a8d8e99bfc39a2c5d0d29bc0da812b52cee65b6ec95ec3ef1cf88aea2e0c85`
4. Successful transaction:
   `/private/tmp/desktidy-live-cutover-e558f74.log`

   SHA-256:
   `3c8a45ee1e83a56a76fbd64baa8fe01d435dd01c6df895d4bfbf126d514424c5`

Each failed attempt stopped before dual Desktop authority. The legacy sorter
was never loaded alongside `com.desktidy.sort`.

## Bound backups and registration archive

- Original rollback epoch:
  `/Users/sicarii/Library/Application Support/DeskTidy Migration Backups/20260815T062846Z`

  `SHA256SUMS` verifies; manifest SHA-256:
  `e7a27d0e8fe298395eedefecb0c3a162464d9a4fd994c71ea71d30b608a52e54`
- Existing DeskTidy support backup:
  `/Users/sicarii/Library/Application Support/DeskTidy Existing Support Backups/20260815T083100Z-e558f74`

  `SHA256SUMS` verifies; manifest SHA-256:
  `d7e9ab8ce791e9d56c84deb74601b69d9cf61c9dd2641b4b82fc366961b1675d`
- Legacy registration archive:
  `/Users/sicarii/Library/Application Support/DeskTidy Legacy Registration Archives/20260815T085000Z-f128fe6`

  `SHA256SUMS` verifies; manifest SHA-256:
  `e1b35418b089a869353ebd76f7826c964931f162287e9d4c661a0a4cb0c984e0`

## Directory compatibility defect

The first live DeskTidy sweep treated the retained root directories `Archive`,
`Docs`, `Media`, and `Projects` as ordinary dropped folders and moved them under
`Folders/`. Directory movement receipts were not Undo-eligible.

DeskTidy was unloaded while repairing. All four directories were restored with
same-volume `os.rename`; their original inodes were retained. Restoration
receipt:

`/private/tmp/desktidy-live-directory-restoration-e558f74.json`

SHA-256:
`610a7ef10721aec520340be252b77d92138c29eb512ed3f10205b6ede3f99382`

The shared reserved-root set now protects all four names in both the automatic
watcher and manual Tidy Now. R0 C31 and Phase G G14 cover the two paths.

## Undo defect discovered after migration

The authorized PDF canary moved successfully. The first actual
`CanonicalApplicationCore.live().undo` restored the same bytes and inode and
wrote a durable reversal receipt, but the automatic sorter re-filed the restored
file two seconds later. The unbundled harness also raised an Objective-C
notification-center exception after the durable completion events.

The repair:

- uses the existing `desktidy.lock` as one cross-process lock for watcher,
  Tidy Now, and Undo movement transactions;
- reconstructs the latest exact durable Undo restorations from the valid
  ledger and skips those artifacts during automatic sweeps;
- keeps explicit Tidy Now as the user-authorized override;
- refuses automatic movement when ledger integrity is invalid;
- skips native notification setup for an unbundled live-core caller.

The same canary then completed a stable A→B→A cycle. The automatic watcher was
observed logging the exact-restoration skip before canary removal. Full lineage
is in [`R2_LOCAL_PRODUCTION_DEPLOYMENT.md`](R2_LOCAL_PRODUCTION_DEPLOYMENT.md).

## Live state after remediation

Direct readback:

```text
ABSENT com.sicarii.desktop-autosort
ABSENT com.sicarii.desktop-autosort-notify
LOADED com.desktidy.sort
LOADED com.desktidy.notify
AuthorityGuard verdict SOLE
overall runningHealthy
effective mover com.desktidy.sort
targetSource nativeConfig
ledger valid(8)
```

The old active registration plists remain absent. The old implementation and
rollback plists remain retained but inactive. `Archive`, `Docs`, `Media`, and
`Projects` remain at the Desktop root with the restored inodes.

## Claim boundary

The result is a local production deployment that is operational and
rollback-backed. The installed app is ad-hoc signed. Developer ID signing,
notarization, TestFlight, App Store, and public installer/release remain blocked
on Apple Developer Program access. Keyboard focus-ring traversal, spoken
VoiceOver output, reboot/login persistence, and any other unobserved lifecycle
surface are not promoted to PASS.
