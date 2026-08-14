# Phase 1B Operator Runbook — Sacrificial SMAppService Observation

Phase 1A.1 seals measurement and grant preparation only. Authorization
alone is **not** the next step.

Phase 1B still requires:

1. a reviewed minimal patch connecting the sealed `PreparedMutationGrant` to
   exactly one production adapter call;
2. separate architect authorization for that patch and the observation.

Do not run a real mutation path until both exist. Fake-substrate tests are
not that observation.

Token creation must use the **measured probe executable SHA-256** and the
**compiled 40-hex source commit** from the built probe (`--plan` prints the
commit). Nonce reservations are durable and non-reusable under the
sacrificial support root. Foreign/protected-root evidence is measured twice.

Runtime label, Login Items string, status semantics, FDA/TCC, reboot/login,
and Apple distribution remain **unknown**. No automatic production
self-label widening.

## Non-claims (Apple membership)

Developer ID, notarization, TestFlight/App Store, public DMG, and production
profiles are unavailable. Ad-hoc signing is development evidence only.

Compilation of `SMAppService` is capability, not proof of runtime registration.

## Identities (hypotheses until observed)

| Item | Value | Status |
|---|---|---|
| Probe bundle id | `com.desktidy.sacrificial-probe` | coded |
| Embedded plist | `Contents/Library/LaunchAgents/com.desktidy.sacrificial.plist` | coded |
| Hypothesized label | `com.desktidy.sacrificial` | **UNOBSERVED** |
| Production self labels | `com.desktidy.sort`, `com.desktidy.notify` | unchanged |

Do **not** add any observed label to `ProductIdentity.selfLabels` automatically.

## Prerequisites

1. Phase 1A PR reviewed; source commit recorded (40- or 64-hex SHA).
2. Sacrificial probe built with `scripts/build-probe.sh` into a `/tmp` output root.
3. Bundle SHA-256 of the built `.app` recorded.
4. Protected live labels remain `com.sicarii.desktop-autosort` and
   `com.sicarii.desktop-autosort-notify`.
5. Architect is present for Login Items / FDA visual readback.

## Sacrificial root

Create a directory **outside** `~/Desktop` and not symlink-equivalent to it,
e.g. `/tmp/desktidy-phase1b-<nonce>`. Never use the live Desktop.

## Pre-observation inventory

Record, read-only:

- `git rev-parse HEAD`
- `shasum -a 256` of the probe bundle executable
- `launchctl print` is **not** required until Phase 1B; if used, print only,
  never bootstrap/bootout/kickstart/enable/disable
- confirm personal labels are not mutation targets

## Authorization

The architect writes **one** one-time authorization file (strict JSON, schema 1,
exact keys, no duplicate keys) binding:

- `operation` (`register` then a second file for `unregister`)
- `sacrificialRoot`
- `bundleSHA256`
- `sourceCommit`
- `expiry`
- `nonce` (unique; never reused)

Phase 1A must not create a valid live file. Phase 1B creates it by hand.

## Probe command

Default is read-only:

```text
DeskTidySacrificialProbe.app/Contents/MacOS/DeskTidySacrificialProbe --plan
```

Mutation (Phase 1B only):

```text
…/DeskTidySacrificialProbe --register --auth-file /path/to/auth.json
…/DeskTidySacrificialProbe --unregister --auth-file /path/to/unreg.json
```

Without `--commit-mutation` those commands still stop at exit 4.

Phase 1A.1's probe still **refuses to invoke** the production mutator even
if the interlock would permit (exit 4). Phase 1B adds an explicit second
factor: `--commit-mutation`. Hosted CI and the public-boundary suite must
not pass that flag with a valid authorization.

```text
…/DeskTidySacrificialProbe --register --auth-file /path/to/auth.json --commit-mutation
…/DeskTidySacrificialProbe --unregister --auth-file /path/to/unreg.json --commit-mutation
```

Ungranted `requestRegister`/`requestUnregister` stay disconnected. Only the
grant-accepting overloads call `SMAppService.register` / `.unregister`.

## Exact readbacks after a real grant

1. `SMAppService.status` for the embedded plist name
2. `launchctl print gui/<uid>/<observed-label>` — print only
3. Login Items visible string (human screenshot/notes)
4. Helper heartbeat under the sacrificial app-support root
5. Target confinement: heartbeat/target not on Desktop
6. Migration transaction record fields
7. FDA/TCC: observe whether a prompt appears; do **not** enter credentials
   into an agent-driven prompt. Architect operates the UI.
8. Reboot/login is a **later subphase**, not performed here.

## PASS / BLOCKED / INDETERMINATE / rollback-required

| Verdict | Meaning |
|---|---|
| PASS | Granted operation ran; status and label readbacks agree; no live Desktop/personal-label involvement; unregister restored absence |
| BLOCKED | Interlock refused, or a protected root/label would have been touched |
| INDETERMINATE | API returned unknown / status unreadable; must not claim success |
| rollback-required | Dual presence or unknown post-state; unregister and stop |

## Rollback and timeout

If register is granted and anything is unknown or dual, run the unregister
authorization within a bounded window (architect-chosen, e.g. 15 minutes).
If unregister fails or is unknown, mark rollback-required and stop.

## Post-run absence proof

After unregister: status notRegistered/notFound, no Login Item string for the
probe, heartbeat file may remain as a sacrificial artifact.

## Deletion rules

Delete only probe-owned `/tmp` sacrificial roots and authorization files.
Do not delete `~/Desktop` contents or personal-mover state.

## What this runbook does not do

No merge, tag, release, notarize, Homebrew, self-label widening, reboot, or
FDA grant by an agent.
