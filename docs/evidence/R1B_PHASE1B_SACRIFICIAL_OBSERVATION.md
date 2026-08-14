# R1B Phase 1B — sacrificial SMAppService observation

Date: 2026-08-14
Commit built and observed: `4725c5143af18a78df303eaaeb36c9221caedc04`
Command: `scripts/observe-phase1b.sh`
Ad-hoc signed probe only. Not Developer ID / not notarized.

Sacrificial root: `/tmp/desktidy-phase1b-root-Oxdsga` (outside Desktop).
Probe executable SHA-256: `3bea32e436110dea7115e609285227b4bf1f6956a9149d0710cab2ba61dda63d`

No `launchctl bootstrap/bootout/kickstart/enable/disable`.
No live Desktop traversal or file creation.
No personal-mover mutation.

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
executableSHA256=3bea32e436110dea7115e609285227b4bf1f6956a9149d0710cab2ba61dda63d
sourceCommit=4725c5143af18a78df303eaaeb36c9221caedc04
MUTATION_ATTEMPTED
adapter_result=success
status=enabled
ledger_constructions=1
ledger_registers=1
register_exit=0
```

`launchctl print gui/501/com.desktidy.sacrificial` rc=0:

```
gui/501/com.desktidy.sacrificial = {
active count = 0
path = (submitted by smd.12013)
type = Submitted
managed_by = com.apple.xpc.ServiceManagement
state = not running
program identifier = Contents/MacOS/SacrificialHelper (mode: 2)
parent bundle identifier = com.desktidy.sacrificial-probe
BTM uuid = FBD7DF70-2294-4324-ADD7-AEDA8F374535
runs = 0
last exit code = (never exited)
}
```

Observed launchd label: **`com.desktidy.sacrificial`**.
Helper did not run (`RunAtLoad`/`KeepAlive` false). Heartbeat absent.
Login Items visible string: **not read** (no System Settings UI).
FDA/TCC: **not observed**.

## Unregister

```
GRANT_PREPARED
operation=unregister
MUTATION_ATTEMPTED
adapter_result=success
status=notRegistered
ledger_unregisters=1
unregister_exit=0
```

`launchctl print gui/501/com.desktidy.sacrificial` rc=113 (not loaded).

## Post-observation live print

| Label | rc |
|---|---|
| `com.desktidy.sort` | 113 |
| `com.desktidy.notify` | 113 |
| `com.desktidy.sacrificial` | 113 |
| `com.sicarii.desktop-autosort` | 0 |
| `com.sicarii.desktop-autosort-notify` | 0 |

## What this does not authorize

Do **not** add `com.desktidy.sacrificial` to `ProductIdentity.selfLabels`
from this transcript alone. Production migration, merge, Login Items
visual, FDA, and reboot/login remain separate architect decisions.
