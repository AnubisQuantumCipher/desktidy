# R1B Phase 1B — sacrificial SMAppService observation

Date: 2026-08-14
Commit built and observed: `673f49182dad83fd3dc81513927edc2057620abc`
Command: `scripts/observe-phase1b.sh`
Ad-hoc signed probe only. Not Developer ID / not notarized.

Sacrificial root: `/private/tmp/desktidy-phase1b-root-dv5FP4` (outside Desktop, mode 0700, current-user-owned, no foreign overlap).
Probe executable SHA-256: `2f621c2f9979d33782aa89fabd1d4e9abbdf99a19afa1e46e6d86aa2fbb285f6`
Helper SHA-256: `3dfbfb84fd7953cc5b6c4219decf862df251cd20b7bf6e727b09a8b12c20dd7c`
Embedded plist SHA-256: `0636033219e20183401573a8b929913e0ecfa9b3f90fd57a614cf55f2601c2c2`
Register authorization digest: `3dd1e2517f2ca46884393922bec1685d632161b6bbefa32a1bf80e9e00abe889`
Unregister authorization digest: `9fa452ffdcc330e902f4a18726a507ed8f9c1ff707f5313b93873babb1a2eecb`
Authorization file bytes were deleted after the lifecycle.

No `launchctl bootstrap/bootout/kickstart/enable/disable`.
No live Desktop traversal or file creation.
No personal-mover mutation.
No Login Items / FDA / TCC UI click.

## Pre-observation `launchctl print` (read-only)

| Label | rc |
|---|---|
| `com.desktidy.sort` | 113 not loaded |
| `com.desktidy.notify` | 113 not loaded |
| `com.desktidy.sacrificial` | 113 not loaded |
| `com.sicarii.desktop-autosort` | 0 loaded |
| `com.sicarii.desktop-autosort-notify` | 0 loaded |

## Register

```
GRANT_PREPARED
operation=register
executableSHA256=2f621c2f9979d33782aa89fabd1d4e9abbdf99a19afa1e46e6d86aa2fbb285f6
sourceCommit=673f49182dad83fd3dc81513927edc2057620abc
root=/private/tmp/desktidy-phase1b-root-dv5FP4
nonce=nonce-r2-reg1
transactionID=06f88019b9a2038879aa4aae912d13359a289eedac7d4e9a30a45f0b7799eb9f
MUTATION_ATTEMPTED
dispatch_result=invoked
status=enabled
ledger_constructions=1
ledger_registers=1
ledger_unregisters=0
register_exit=0
```

`launchctl print gui/501/com.desktidy.sacrificial` rc=0. Observed fields:

- launchd label: **`com.desktidy.sacrificial`**
- `managed_by = com.apple.xpc.ServiceManagement`
- `path = (submitted by smd.12013)`
- `state = not running`
- `program identifier = Contents/MacOS/SacrificialHelper (mode: 2)`
- `parent bundle identifier = com.desktidy.sacrificial-probe`
- `XPC_SERVICE_NAME => com.desktidy.sacrificial`
- `runs = 0`
- `last exit code = (never exited)`

Helper did not run (`RunAtLoad`/`KeepAlive` false). Heartbeat absent.
Login Items visible string: **not read** (no System Settings UI).
FDA/TCC: **not observed**.
Reboot/login: **not performed**.

## Unregister

```
GRANT_PREPARED
operation=unregister
executableSHA256=2f621c2f9979d33782aa89fabd1d4e9abbdf99a19afa1e46e6d86aa2fbb285f6
sourceCommit=673f49182dad83fd3dc81513927edc2057620abc
root=/private/tmp/desktidy-phase1b-root-dv5FP4
nonce=nonce-r2-unreg1
transactionID=b831b37b90611d368b7cd3813bd663d9ea7f24981f917c8331cd1b3929c9b60b
MUTATION_ATTEMPTED
dispatch_result=invoked
status=notRegistered
ledger_constructions=1
ledger_registers=0
ledger_unregisters=1
unregister_exit=0
```

`launchctl print gui/501/com.desktidy.sacrificial` rc=113 (not loaded).

Rollback elapsed: 0 seconds. Watchdog did not fire.

## Post-observation live print

| Label | rc |
|---|---|
| `com.desktidy.sort` | 113 |
| `com.desktidy.notify` | 113 |
| `com.desktidy.sacrificial` | 113 |
| `com.sicarii.desktop-autosort` | 0 |
| `com.sicarii.desktop-autosort-notify` | 0 |

Independent post-run reread: production and sacrificial absent; both personal labels still loaded.

## Adapter / transaction ledger (redacted)

Precall:

```
06f88019b9a2038879aa4aae912d13359a289eedac7d4e9a30a45f0b7799eb9f nonce-r2-reg1 register <exe> <commit> 3dd1e2517f2ca46884393922bec1685d632161b6bbefa32a1bf80e9e00abe889
b831b37b90611d368b7cd3813bd663d9ea7f24981f917c8331cd1b3929c9b60b nonce-r2-unreg1 unregister <exe> <commit> 9fa452ffdcc330e902f4a18726a507ed8f9c1ff707f5313b93873babb1a2eecb
```

Postcall:

```
06f88019… nonce-r2-reg1 register invoked enabled
b831b37b… nonce-r2-unreg1 unregister invoked notRegistered
```

## What this does not authorize

Do **not** add `com.desktidy.sacrificial` to `ProductIdentity.selfLabels`
from this transcript. This is one sacrificial observation on this Mac. It
does not prove reboot/login, Login Items pixels, FDA/TCC, or production
Desktop migration. A future production app-agent label remains unobserved.
