# R1B Service Identity Registry

The accepted production self set remains `com.desktidy.sort` and
`com.desktidy.notify`. The sacrificial SMAppService observation on
2026-08-14 recorded launchd label `com.desktidy.sacrificial` under
parent bundle `com.desktidy.sacrificial-probe`. That label is **not**
a production self-label.

Executable catalog: `src/ServiceIdentity.swift`. ProductIdentity
delegates its accepted self set to that registry.

## Current accepted identity (Phase 0, executable)

| Role | Label | Expected program basename |
|---|---|---|
| sorter | `com.desktidy.sort` | `desktidy-sort` |
| notifier | `com.desktidy.notify` | `desktidy-notify` |
| menu-bar app (not an agent) | bundle id `com.desktidy.app` | `DeskTidy` |

A label from this set with a **contradictory existing executable** (basename
outside the expected set) is **not** self. A future or unloaded label such as
`com.desktidy.app.sort` is **not** self.

## What Phase 1 must add — only after sacrificial observation

`SMAppService.agent(plistName:)` typically registers a bundle-scoped agent
whose launchd label is not the CLI pair above. Until that label is observed
on a sacrificial, non-live root, it must not be added to `ProductIdentity.selfLabels`.

Proposed binding to confirm in the authorized Phase 1 observation:

1. **Label** — exact string printed by `launchctl print` after
   `SMAppService.agent(plistName:).register()` (likely
   `com.desktidy.app.<plist-stem>` or the embedded plist's `Label`).
2. **Program** — the bundle executable or a `BundleProgram` relative path
   inside `Contents/Library/LaunchAgents`.
3. **Bundle id** — `com.desktidy.app`.
4. **Coexistence** — if a legacy `com.desktidy.sort` plist and the new app
   label both watch the same root, EffectiveState must be `ambiguous` /
   refuse. Never treat dual self-presence as healthy.
5. **Atomic catalog update** — `selfLabels`, expected basenames, and the
   target resolver's product-plist name must change in the same commit as
   registration code. A half-updated catalog is an accept-condition change
   and is prohibited.

## Explicitly not authorized by Phase 0

- Adding any SMAppService/app-agent label to the accepted self set
- Treating label-only match as self when program evidence contradicts it
  (Phase 0 already fails closed on that evidence)
- Registering, unregistering, or launching a new agent
