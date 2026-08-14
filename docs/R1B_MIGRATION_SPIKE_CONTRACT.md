# R1B Spike Contract — SMAppService Migration (NOT IMPLEMENTED — future authorized mission)

_Written during R1A as required, from what R1A actually discovered. Nothing in
this document is built. It defines the bounded spike that must precede R1B._

## What R1A established (inputs to this contract)

1. The effective-state model derives truth from launchd evidence + canonical
   roots + ledger verification — it never trusts plist presence. The migration
   must preserve that: registration change may not introduce a second source
   of "running" truth.
2. The R0 authority guard treats DeskTidy's own labels (`com.desktidy.sort`,
   `com.desktidy.notify`) as self. An SMAppService-registered agent gets a
   bundle-scoped label (`com.desktidy.app.*` or the plist name under
   `Contents/Library/LaunchAgents`). **Discovery:** the self-label set and the
   guard's enumeration must learn the new label(s) atomically with the
   migration, or the app would flag itself as a foreign conflict.
3. CLI installs write plists with `DESKTIDY_TARGET_DIR` in
   `EnvironmentVariables`; the state model reads the target from there.
   SMAppService embeds a static plist inside the bundle — per-user target
   selection must move to a config file read by both surfaces
   (`~/Library/Application Support/DeskTidy/config.json` is the candidate),
   and the state model's target-derivation order must be updated in the same
   change, with parity gates extended accordingly.

## Spike scope (time-boxed, throwaway branch)

Prove, on an isolated fixture user-context only:
- `SMAppService.agent(plistName:)` register/unregister round-trip;
- resulting launchd label as observed by `launchctl print` (feeds the guard's
  self-label set);
- Login Items visibility string;
- coexistence: legacy CLI plists present + SMAppService registration attempted
  → must be detected by the authority guard as a same-root duplicate of
  ourselves and REFUSED until the legacy plists are removed by the SAME
  explicit user action (no silent unload of anything, ever);
- behavior when FDA is granted to the old CLI binary path but the app bundle
  binary is new (expect: TCC re-grant needed; document exact UX).

## Hard conditions carried from R0/R1A

- Never modify a non-DeskTidy agent. Never take over a root silently.
- The migration path must fail closed at every step; a half-migrated state
  must render as `ambiguous` (never healthy) in both surfaces.
- All gates run on fixtures; the live personal mover on the architect's Mac
  is out of bounds.
- The A→B→A tamper discipline applies to the migration guard itself.

## Exit criteria for the spike

A written report (not code merged to main) answering: final label set, the
config-file schema for target selection, the exact legacy-detection rule, the
TCC/FDA re-grant story, and the parity-gate additions R1B must ship with.
