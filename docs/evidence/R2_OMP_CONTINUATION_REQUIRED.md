# DeskTidy OMP restart-safe continuation

Checkpoint parent: `9acd71fe004f01cfb8d68d4d39de7c7bb81d6012`
Branch: `r2/full-local-native-completion-omp`
Base: `cbfb795b0f0a8324b4e3152455ad6f22d98b44d7`

## Completed

- Identity gate: continuation and parent SHA-256 values verified; Phase 1B local/upstream/PR #4/hosted macOS 14+15 identity matched the handoff.
- Phase A: all fresh non-live gates were run; exact results and authority readback are in `R2_OMP_PHASEA_INDEPENDENT_AUDIT.md`.
- The historic lifecycle is classified `PHASE1B_EVIDENCE_BLOCKED_INCOMPLETE_HISTORICAL_TRANSCRIPT`; no replay is authorized.
- `scripts/observe-phase1b.sh` has a tested fail-closed retirement fuse. `scripts/test-phase1b-retirement.sh` passed.

## Open findings

1. Historical Phase 1B raw lifecycle bindings are missing; do not treat the old Markdown transcript as independently accepted.
2. The prescribed Phase 1A.1 `42/42` differs from the actual base outputs: unit `24/24`, public boundary `32/32`.
3. Required `git push -u origin r2/full-local-native-completion-omp` was denied before execution by `tools.approval.bash: deny`. No continuation branch, draft PR, or hosted CI exists for the local Phase A checkpoint.
4. Phase B architecture is present only as pure/unwired primitives. `src/ProductIdentity.swift` is flat constants; `src/MigrationState.swift` and `src/MigrationTransaction.swift` are fake-only state machinery; typed product identity registry, durable migration transaction, health-before-legacy-removal, and production-surface wiring remain unimplemented.

## Safety state

Last read-only launchctl inventory: DeskTidy sort/notify/sacrificial all absent (rc 113); personal mover and notifier loaded (rc 0). No DeskTidy lifecycle mutation, production migration, personal mover mutation, or live Desktop file access occurred.

## Active task and next command

Active task: Phase B typed product identity/service registry and fake-only recoverable migration architecture.

First command after the environment permits push:

```text
git push -u origin r2/full-local-native-completion-omp
```

Then create exactly one draft stacked PR targeting `r1b/phase1b-sacrificial-observation`. Before Phase B code, write and observe a failing hermetic test for the typed registry; retain fake-only adapters and do not replay the lifecycle.

## OMP continuation update — 2026-08-14

Committed local checkpoints:

- `29efd7a R2 Phase B: seal recoverable migration substrate`
- `88e6010 R2 Phase C: add canonical application core`
- `93c6d50 R2 Phase D: add native configuration menu`

Fresh verification before this boundary:

- full pre-Phase-C regression roster passed after `88e6010`;
- Phase C gates: `6 passed, 0 failed`, including stale undo-receipt replay protection;
- native bundle build passed at `/private/tmp/desktidy-phase-d-app/DeskTidy.app`;
- hermetic `foreignConflict` `--smoke` passed; the no-fixture smoke isolation guard passed.

Uncommitted Phase-D configuration work is intentionally not a checkpoint:

- `src/NativeConfigParser.swift`, `src/CanonicalApplicationCore.swift`, `src/DeskTidy.swift`, and `scripts/build-app.sh` modified;
- `src/NativeConfiguration.swift`, `src/NativeConfigurationStore.swift`, and `src/PhaseDTests.swift` untracked;
- current compile succeeds, but `--phased-test` is red only at `D03`: schema-1 migration returns `protected or symlinked root` for a hermetic `/private/tmp/.../app` store.

Do not claim Phase D complete. Next action: root-cause the false protected/symlink classification in `NativeConfigurationStore.prepareRoot()` / `noSymlink(_:)` using the `D03` fixture, fix it, re-run `--phased-test`, then rebuild and smoke the app before committing the configuration slice. Preserve all non-live constraints and do not push.

## OMP continuation update — Phase E

- `92a8bcd R2 Phase D: harden native configuration` is committed. `--phased-test` reported `4 passed, 0 failed`; the rebuilt native app’s hermetic smoke ended `SMOKE overall=foreignConflict`.
- Phase E is uncommitted: `src/CanonicalApplicationCore.swift`, `src/PhaseETests.swift`, `src/DeskTidy.swift`, and `app/DeskTidyApp.swift`.
- Phase E source compile/test attempts did not yield a result: the 600-second and 90-second `swiftc && --phasee-test` invocations timed out after compiler warnings, and launching the existing Phase-E binary through the supervised process runner emitted no output before it was stopped.

Next action: distinguish a compiler/link stall from a test deadlock with a narrow compile-only command, then run individual E01–E06 contracts with an unbuffered harness. Do not commit or claim Phase E until all contracts terminate and pass.

## OMP continuation update — Phase M packaging handoff

- Committed local checkpoints through Phase L:
  `be1669f` (receipt notifications), `c035070` (collision-safe Undo),
  `4c62750` (validated history), `ba02f6e` (bounded App Intents),
  `f4abd19` (lifecycle model), `9012319` (suggestion-only controls), and
  `e5fdd9e` (finite hostile property campaign).
- Phase L evidence was rerun after its adjudicator confinement repair:
  `PHASE L CAMPAIGN: 14 passed, 0 failed, 0 timed out, 14 total`;
  the independent adjudicator accepted exactly 14 finite records and the
  summary reported the fixed seed `83971444967444`, unique IDs, nonzero
  checks, and no unknown status. This is finite regression evidence, not
  universal proof.
- Uncommitted Phase M implementation: `scripts/build-app.sh`,
  `scripts/package-local-rc.sh`, `scripts/verify-local-rc.sh`, and
  `scripts/plan-local-rc-lifecycle.sh`. It has not been built, packaged,
  independently reviewed, or executed. No local RC artifact exists.
- No live Desktop, personal mover, service registration, reboot/login,
  notification permission dialog, shortcut invocation, push, merge, deploy,
  or public release occurred in this continuation.

### Restart-safe next action

Read and review the uncommitted Phase M scripts. Create the missing
`scripts/test-local-rc-packaging.sh` and local-RC documentation if still
needed. Then build a fresh app to `/private/tmp`, package it to a fresh
`/private/tmp` location, run package verification and fixture-only smoke,
and record the resulting artifact hash/manifest. Do not claim Phase M
complete until those exact commands pass. Preserve all non-live constraints.
