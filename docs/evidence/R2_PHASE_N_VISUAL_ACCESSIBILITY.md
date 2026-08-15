# DeskTidy Phase N — native status surface and accessibility evidence

Date: 2026-08-15
Scope: fixture-bound macOS status-bar app; no live Desktop mutation

## Mechanized evidence

- `scripts/test-native-status-surface.sh` launches the exact built
  `DeskTidy.app` through LaunchServices with every DeskTidy path under
  `/private/tmp`, selects `--ui-preview`, requires one CoreGraphics window
  titled `DeskTidy Status Preview`, captures that exact window, hashes it, and
  terminates the process.
- `scripts/window-probe.swift` performs the window-owner/title/bounds check
  without Automation or Accessibility permission.
- `scripts/full-local-release-gates.json` includes required gate
  `native-status-surface`; `scripts/run-full-local-release-gate.py` executes it
  only after `app-build` passes and retains the PNG in the gate work directory.
- The sealed fixture capture is
  `docs/evidence/assets/R2_PHASE_N_STATUS_SURFACE.png`.
- SHA-256:
  `487d1e8d9fb714815ebf0bb028d7909f6f2e73c8fdd482995f8a91b8fbb25936`.
- The expanded R1A policy tests prove that onboarding, busy, foreign-conflict,
  ambiguous, and degraded-ledger states expose no movement controls; healthy
  state exposes Tidy/Pause/eligible Undo; durable pause exposes Resume only.
- Phase H tests prove that a validated reversal receipt is presented as
  `Restored` with live status `present`, rather than as an unsafe forward move.

## Directly observed fixture matrix

The same `NativeMenuContent` used by `MenuBarExtra` was observed through the
preview scene with `computer_use` pixels and AX controls:

- onboarding: neutral tray, `Not running — agent not loaded`, folder setup only;
- healthy: green tray, sole authority, running agent, Tidy Now and Pause;
- Tidy Now: `invoice.pdf` moved to `Documents/invoice.pdf` and a validated Undo
  control appeared;
- Undo: the original root path returned, the destination disappeared, and the
  reversal row displayed `Restored · Current item verified`;
- paused: filled pause icon, `Paused — file movement is disabled`, Resume only;
- resumed: durable pause state returned to `running`;
- foreign conflict: long owner label wrapped and no movement controls appeared;
- unreadable agent definition: light appearance, exact ambiguity reason, no
  movement controls;
- tampered ledger: high-contrast dark appearance, exact digest failure, history
  unavailable, no movement controls.

The fixture movement and reversal both preserved SHA-256
`a842ff97b17be0ff9ca00c7198ba3efe30365ab19c5203a9234f4a2e34f82115`.

The normal, non-preview app was also launched without `open -g`; a new tray icon
appeared in the real macOS menu bar and disappeared when that exact fixture PID
was terminated. `open -g` suppressed first presentation and is not the normal
interactive launch path.

## Claim boundary

**PARTIAL — native status surface is mechanized; full accessibility remains
indeterminate.**

Verified: a built app presents the shared native status content, captures into
a non-empty image, exports labelled AX buttons in direct inspection, fails
closed across adverse states, and performs/undoes a fixture move byte-exactly.

Unverified:

- direct click-through of the production `MenuBarExtra` popup, because the
  desktop driver cannot bind an `LSUIElement` process with no ordinary window;
- keyboard focus-ring traversal, because host Full Keyboard Access was disabled
  and was not changed globally;
- spoken VoiceOver output;
- notification-permission UI and migration/rollback UI pixels.

Therefore the broad canonical `visual-accessibility` gate remains
`indeterminate`; the narrower `native-status-surface` gate is executable and may
pass. Source labels are not substituted for the unobserved accessibility lanes.

## Safety

All movement used `/private/tmp/desktidy-visual-*` fixtures. No test targeted the
live Desktop, registered a service, changed global accessibility settings,
clicked a permission dialog, or unloaded/restarted the personal mover.