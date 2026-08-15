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

## OMP continuation update — Phase L through M

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
- `34df60d R2 Phase M: add local RC packaging controls` and
  `601e817 R2 Phase M: reject archive symlinks before extraction` are local
  checkpoints.
- The current local-only ad-hoc RC was built from source commit
  `601e8177db125ad6d36bb65a4a54eb46e81a6a91`, packaged and independently
  verified from fresh `/private/tmp` locations. The package archive SHA-256 is
  `57aee31ff27bea06a83eb6b2a04acd6a6d5a4474855d38998fdfe5c528c7a549`;
  its sidecar manifest SHA-256 is
  `e4e7e8fa81a94239e22fb388d5cb2c96e7c73001443930c1c012eed071371bbc`.
- Verification confirmed the manifest, embedded build identity, arm64/macOS
  14.0 metadata, ad-hoc signature, and a fresh fixture smoke result
  `SMOKE overall=pausedNotLoaded`. Gatekeeper assessment was `rejected`;
  this is expected local/ad-hoc evidence and is not a public-trust result.
- `scripts/test-local-rc-packaging.sh` passed and proves the verifier rejects
  a crafted ZIP symlink before extraction. The actual package/verification
  touched no Desktop, service, login item, personal mover, or user files.

### Restart-safe next action

Phase N must inspect the exact Phase M artifact in the actual macOS surface
and record screenshots/accessibility trees for the supported fixture states.
Do not click permission dialogs or touch the live Desktop. Then reconcile
documentation claims, construct the canonical gate, and run the hosted
clean-clone reseal.

## OMP continuation update — Phases N and O

- `4a2b5e0 R2 Phase N: record visual evidence limitation` records the exact
  local RC fixture launch. The app process was observed, but the captured host
  image showed the foreground terminal rather than a DeskTidy menu extra. No
  accessibility tree was requested because that would enter a prohibited
  permission path. Phase N is **INDETERMINATE**, not a visual/VoiceOver pass.
- `a45ef9e R2 Phase O: reconcile local RC claims` replaces stale public
  installer, Homebrew, reboot/login, signing, service, and website claims with
  the bounded local-RC state. It adds `scripts/claims-scan.py` and
  `scripts/test-claims-scan.sh`; the contract test passed with 22 scanned
  files, 5 rules, 0 active matches, 0 excluded matches, and successful
  mutation/zero-work/malformed-summary controls.
- The website source was updated but not deployed. Its Next.js build was
  attempted and skipped after `next: command not found`; this worktree has no
  `website/node_modules/.bin/next`. No dependency installation or deployment
  was attempted.

### Restart-safe next action

Phase P must construct the canonical full-local-release gate and independent
validator. It must preserve Phase N as indeterminate rather than convert it
into release success, and must carry the website build dependency absence as a
skipped verification rather than a pass.
