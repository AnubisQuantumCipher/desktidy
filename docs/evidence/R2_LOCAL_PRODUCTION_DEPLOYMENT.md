# DeskTidy R2 — local production deployment receipt

Date: 2026-08-15

Repository: `AnubisQuantumCipher/desktidy`

Branch: `r2/full-local-native-completion-omp`

PR: <https://github.com/AnubisQuantumCipher/desktidy/pull/6>

Authorized contract SHA-256:
`9cb220ed766ef388c06b3d29498b5ccfc2c83863024d0173307315a942ef0003`

Starting checkpoint:
`ff03c82436098899f9d82542303832994e06887a`

Undo/remediation checkpoint:
`42baf3380751e110ad297498fbc25346c6879fef`

App-presentation and deployed code checkpoint:
`2874d05a9b2fb1a766e62297c23ec4ff7a42787d`

The commit containing this receipt is a documentation seal over the code
checkpoint above. A commit cannot embed its own SHA; final repository/app/PR
head equality is therefore recorded in the operator handoff after this file is
committed, built, installed, and checked.

Post-seal production hardening, including the no-follow movement-lock repair,
website write-surface retirement, and refreshed canonical/hosted verification,
is recorded in
[`R2_PRODUCTION_HARDENING_2026-08-15.md`](R2_PRODUCTION_HARDENING_2026-08-15.md).

## Verdict

**COMPLETE for the authorized, agent-completable local deployment scope.**

The supported claim is:

> DeskTidy local production deployment is operational and rollback-backed on
> this Mac.

This is not a claim that public Apple distribution is complete. Developer ID
signing, notarization, TestFlight, App Store, and a public installer/release are
blocked on Apple Developer Program access.

## Presentation and migration behavior

- The known personal-sorter pre-migration state uses
  `arrow.triangle.2.circlepath`, says
  `Ready to migrate — existing Desktop sorter is active`, and gives explicit
  fail-closed migration guidance.
- An unknown authority conflict retains `exclamationmark.triangle`, remains
  blocked, and exposes no movement action.
- State/presentation policy passes 74 controls with zero failures.
- Successful migration writes native `config.json`; the installed target is
  `/Users/sicarii/Desktop` and live `targetSource` is `nativeConfig`.
- An existing DeskTidy support directory requires a bound backup. The
  transaction preserves/overlays it on success and restores its exact bytes on
  failure.
- A missing unrelated WatchPath is accepted only when it is provably unrelated
  to the target. Same-target foreign or unreadable authority continues to fail
  closed.
- Quiescence is process-exact and cannot match the migration command or its own
  `pgrep` line.
- Successful bootout removes the two prior active registration plists from
  `~/Library/LaunchAgents`. Exact rollback copies and the former implementation
  remain retained and inactive.

Focused migration result:

```text
LIVE_MIGRATION_TEST=PASS cases=10
```

## Failed-closed live attempts preserved

The cutover was not a frictionless sequence:

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

No attempt loaded the prior sorter alongside DeskTidy.

## Directory compatibility defect and exact restoration

The first live DeskTidy sweep incorrectly moved `Archive`, `Docs`, `Media`, and
`Projects` into `Folders/`. Directory receipts were not Undo-eligible.

DeskTidy was unloaded while repairing. Same-volume `os.rename` restored all
four exact directories and retained their inodes:

```text
Archive  inode=451900238
Docs     inode=451900244
Media    inode=451900249
Projects inode=451900236
```

Restoration evidence:
`/private/tmp/desktidy-live-directory-restoration-e558f74.json`

SHA-256:
`610a7ef10721aec520340be252b77d92138c29eb512ed3f10205b6ede3f99382`

`Category.reservedRootNames` now supplies one compatibility set to automatic
and manual sweep paths. R0 C31 and Phase G G14 prove all four remain at root and
produce no movement receipts.

## Canary: actual Undo, exposed race, repair, stable A→B→A

Canary:
`DeskTidy Production Canary 9e6b8b7d56.pdf`

Byte identity:
`749317f70666b2bb249b58d18c010f8a1a18a8482433c48e7be26c73d515dbcd`

Size/inode:
`69 bytes`, inode `455875882`

### Original movement

- Source:
  `/Users/sicarii/Desktop/DeskTidy Production Canary 9e6b8b7d56.pdf`
- Destination:
  `/Users/sicarii/Desktop/Documents/DeskTidy Production Canary 9e6b8b7d56.pdf`
- Receipt:
  `0B6AB6FD-18D6-4C1A-8852-C44FC1669D96`
- Outcome: `moved`, `undoEligible=true`

### First actual core Undo and defect

`CanonicalApplicationCore.live().undo(receiptID:)` completed and wrote:

- command receipt `57185970-C619-4144-9274-6C0FA4CDC21D`;
- reversal receipt `6755159B-93F2-4D17-BC0E-06AD8D0249D5`;
- restored SHA-256 and inode equal to the original.

After the durable completion events, the standalone unbundled harness raised
`NSInternalInconsistencyException` while constructing
`UNUserNotificationCenter`. Two seconds later, the still-loaded automatic
sorter re-filed the restored artifact as receipt
`C2C22E32-A60A-48FE-B5D5-F2E48E15CF14`.

That was a real product defect, not hidden as a successful final canary.

### Repair

- One `MovementProcessLock` now serializes the watcher, Tidy Now, and Undo
  against the existing `desktidy.lock` file.
- A valid-ledger snapshot identifies the latest exact Undo restorations.
  Automatic sweeps skip only an unchanged path/inode/metadata/content identity.
- A later successful move consumes suppression; changed/replaced artifacts are
  not suppressed. Explicit Tidy Now remains the user-authorized override.
- Automatic startup refuses a damaged ledger before reconciliation or movement.
- An unbundled live-core caller skips native notification setup instead of
  touching `UNUserNotificationCenter`.

Controls:

```text
R0 CONTROLS: 34 passed, 0 failed
PHASE F GATES: 9 passed, 0 failed
PHASE G GATES: 14 passed, 0 failed
R1A GATES: 74 passed, 0 failed
```

### Repaired stable Undo

The same canary, without creating a second live Desktop canary, was undone from
receipt `C2C22E32-A60A-48FE-B5D5-F2E48E15CF14` through the actual live core.

- command receipt:
  `F35BD7E1-4378-42BF-A37C-CFE1680A9C46`, outcome `completed`;
- reversal receipt:
  `F07EA13B-6D1E-4E4F-84EE-95D31CB44045`, outcome `moved`;
- source restored with SHA-256
  `749317f70666b2bb249b58d18c010f8a1a18a8482433c48e7be26c73d515dbcd`;
- destination absent;
- inode still `455875882`;
- ledger valid at 8 receipts, final digest
  `7617fe90ad552007c257fed981191a9d31fa822bbcbdd3fafd9579cc0ed894eb`;
- automatic watcher subsequently logged:
  `SKIP exact Undo restoration at root: DeskTidy Production Canary 9e6b8b7d56.pdf`.

Canary lineage evidence:
`/private/tmp/desktidy-production-canary-undo-2874d05.json`

SHA-256:
`8940992d10d34c9534061f329548dead4419f8bf3f7cd90314aacd5fc9a8d3ed`

Only after that evidence was recorded and hashed was the restored canary
deleted. Source and destination are now both absent, returning the real Desktop
to its pre-canary state.

## Exact local verification

Warning-clean compilation used optimized arm64/macOS 14 sources with warnings
promoted to errors.

Canonical summary:
`/private/tmp/desktidy-production-canonical-2874d05.json`

Summary SHA-256:
`205d268932c823711fac912d02ff05a75138d95d2bb335d6a5545fed118e53a3`

Independent validator:

```text
full-local-release-validator: valid overall=blocked gates=46
40 passed
0 failed
3 indeterminate
3 blocked
```

The non-PASS rows remain bounded rather than promoted:

- `phase1b-evidence`: indeterminate historical lifecycle evidence;
- `visual-accessibility`: indeterminate keyboard focus/VoiceOver output;
- `live-authority-readback`: indeterminate inside the non-live runner, with
  separate direct live readback below;
- `sacrificial-lifecycle`: blocked direct replay;
- `website-build`: static blocked placeholder, with detached clean-clone build
  evidence below;
- `hosted-final-sha`: static blocked placeholder, with exact-SHA Actions
  evidence below.

## Detached clean-clone build and package

Exact clone:
`/private/tmp/desktidy-clean-2874d05-paa2T2/repo`

At exact checkpoint `2874d05a9b2fb1a766e62297c23ec4ff7a42787d`:

- `npm ci --ignore-scripts`: PASS;
- `npm audit`: 0 vulnerabilities;
- Next.js optimized production build and TypeScript: PASS;
- ESLint: PASS;
- `scripts/build-app.sh`: PASS;
- app icon representations: 10, PASS;
- migration bundle: 7 files, exact identity, PASS;
- local RC package and independent manifest/signature/fresh-fixture verify: PASS;
- deep strict code-signature verification: PASS.

Artifact hashes:

- RC archive:
  `da1496615703213744c97d8c34ee0efe2b6c6e7f3aa8d60b5ca9084f4e2c82e6`
- RC manifest:
  `22437a6ece331447e78bc123822fb8e421808be283c8863d3986e0fa4ab3dd94`
- app executable:
  `0ae92985aeea93b7bdd8484e3b5b01ce74431a2a679d042285b8bf1e8dbd2995`
- bundled/live sorter:
  `daa4bff562383b70136769f7aae421126f88924515721cae2a77d2a1dc5ae819`

Gatekeeper rejection is retained as the expected ad-hoc-signing boundary.

## Hosted exact-SHA verification

Run: <https://github.com/AnubisQuantumCipher/desktidy/actions/runs/31875707638>

Run ID: `31875707638`

- exact head:
  `2874d05a9b2fb1a766e62297c23ec4ff7a42787d`;
- `build-and-test (macos-14)`: success;
- `build-and-test (macos-15)`: success;
- app build, icon, migration transaction, native surface, canonical-core
  boundary, and hostile controls: success in both jobs;
- CodeRabbit: success.

## Installed app and service identity at live proof

Installed app:
`/Users/sicarii/Applications/DeskTidy.app`

`DeskTidyBuild.json` and migration `IDENTITY` both named checkpoint
`2874d05a9b2fb1a766e62297c23ec4ff7a42787d`. App icon and migration bundle
gates passed. `codesign --verify --deep --strict` passed. Signing is ad-hoc,
local-only.

Hashes at live proof:

- app executable:
  `0ae92985aeea93b7bdd8484e3b5b01ce74431a2a679d042285b8bf1e8dbd2995`;
- bundled and live sorter:
  `daa4bff562383b70136769f7aae421126f88924515721cae2a77d2a1dc5ae819`;
- bundled and live notifier:
  `2e3ec86dc6b126e418ae65479697a5964922eb2e01ea253b5594c44648019dfb`;
- native config:
  `c5082e8162ca0c28c2c31ae0ddb3d906c07df6b66f0b8af77d0374a46d0a6cf9`;
- sorter plist:
  `eff6b24a3470ad30e364b428f0771bbf8a97f2b5b3ce082a7c0cf7efcfa88357`;
- notifier plist:
  `46c5b7cbbb222ccf3f8c5a384bdc86577a458d5832d4782638b52a586c2a8b2b`;
- movement ledger after canary:
  `bd80f303b0498dce58e35f1da476e9cb4ce1a12865be5d2e16c87e9453be869e`;
- command receipt ledger:
  `d1300074f6fbd1bcf8b7500ea31e09fea038274a44975ae460b04f73bbe444d7`.

The previous installed app and sorter were preserved before upgrade:

- app backup:
  `/Users/sicarii/Library/Application Support/DeskTidy App Backups/20260815T090255Z-2874d05`

  manifest SHA-256:
  `dd5c43d4eafb2e869a6a2f640417c24e2fb79a9f48aedb4ef06bcb015e4a62bd`;
- sorter backup:
  `/Users/sicarii/Library/Application Support/DeskTidy Live Binary Backups/20260815T090255Z-2874d05`

  manifest SHA-256:
  `84099faa35f9609613456f46747e01e7d6941fb518a42f8f3d0626cb24b61916`.

Both manifests verify.

## Rollback assets

- Original migration epoch:
  `/Users/sicarii/Library/Application Support/DeskTidy Migration Backups/20260815T062846Z`

  manifest SHA-256:
  `e7a27d0e8fe298395eedefecb0c3a162464d9a4fd994c71ea71d30b608a52e54`;
- existing-support backup:
  `/Users/sicarii/Library/Application Support/DeskTidy Existing Support Backups/20260815T083100Z-e558f74`

  manifest SHA-256:
  `d7e9ab8ce791e9d56c84deb74601b69d9cf61c9dd2641b4b82fc366961b1675d`;
- legacy registration archive:
  `/Users/sicarii/Library/Application Support/DeskTidy Legacy Registration Archives/20260815T085000Z-f128fe6`

  manifest SHA-256:
  `e1b35418b089a869353ebd76f7826c964931f162287e9d4c661a0a4cb0c984e0`.

Every `SHA256SUMS` file verified. Old sorter files and rollback plists are
retained, but old services/plists are inactive.

## Final direct live state at evidence collection

Authority evidence:
`/private/tmp/desktidy-live-authority-2874d05.json`

SHA-256:
`c9139aa5622043563282d92bd47e005d1e24e507cc8139adff32ceda13923456`

Effective-state evidence:
`/private/tmp/desktidy-live-state-2874d05.json`

SHA-256:
`a9b2477402086313522cd8768235986fd5090f131b1b0dcd4f838fc0fb4bb057`

```text
old labels absent
old registration plists absent
com.desktidy.sort loaded / exit 0
com.desktidy.notify loaded
AuthorityGuard verdict SOLE
overall runningHealthy
effective mover com.desktidy.sort
targetSource nativeConfig
ledger valid(8)
Archive, Docs, Media, Projects present at Desktop root
```

The app terminated for upgrade and relaunched from the installed path. The
sorter was upgraded only while booted out, verified byte-equal to the app
bundle, and resumed only through the installed `com.desktidy.sort.plist`.
Service persistence across that explicit reload is observed. Reboot/login
persistence is not claimed.

## Residual blocked and indeterminate claims

1. Developer ID signing, notarization, TestFlight, App Store, and a public
   installer/release are blocked on Apple Developer Program access.
2. Keyboard focus-ring traversal and spoken VoiceOver output remain
   indeterminate. Pixel and AX-control evidence does not substitute for them.
3. Historical sacrificial lifecycle evidence remains bounded and was not
   replayed. Login Items and any unobserved lifecycle surface are not PASS.
4. No reboot was performed; reboot/login persistence remains unobserved.
5. Gatekeeper rejected the ad-hoc local artifact as expected.
6. The canonical `website-build` and `hosted-final-sha` rows remain static
   blocked placeholders; detached exact-SHA evidence is reported separately.
7. PR 6 remains unmerged. Merge and public release require a separate explicit
   architect decision.

## Completion boundary

All agent-completable source, test, migration, rollback, live authority,
canary, documentation, clean-clone, hosted, installation, and service-reload
work authorized by the contract is evidenced without weakening the safety
model. Public Apple distribution is not complete.
