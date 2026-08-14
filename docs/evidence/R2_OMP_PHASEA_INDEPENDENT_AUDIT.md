# R2 OMP Phase A — independent Phase 1B audit

Date: 2026-08-14
Base commit audited: `cbfb795b0f0a8324b4e3152455ad6f22d98b44d7`
Continuation branch: `r2/full-local-native-completion-omp`

## Scope and safety boundary

This audit did not invoke `SMAppService.register()`, `SMAppService.unregister()`, any production-adapter mutation method, any `launchctl` mutation verb, any Login Items/FDA/TCC UI, or any migration. No live Desktop file was read, created, moved, or used. All executable gates used the isolated source worktree and `/private/tmp/desktidy-omp-phasea-cbfb795`.

The historical lifecycle runner is now permanently fail-closed before its former build/auth/launchctl logic:

```text
scripts/observe-phase1b.sh
observe-phase1b: retired after recorded lifecycle; no replay is authorized
exit 2
```

`scripts/test-phase1b-retirement.sh` was written first, failed because the fuse was absent, then passed after the fuse was inserted. It statically requires that the fuse precede `--commit-mutation` and behaviorally requires the exact exit-2 refusal.

## Identity observations

- Continuation SHA-256: `156d3097855b588e194e23cf74ed0df5545af7019b498cb1358aa100b953dfee`.
- Parent-program SHA-256: `bb4eaa2e8efbfd5e43844feafaa48a24c438ceba9b832a738946bfb0bac51308`.
- Phase 1B local HEAD and `origin/r1b/phase1b-sacrificial-observation`: `cbfb795b0f0a8324b4e3152455ad6f22d98b44d7`; branch clean.
- PR #4: OPEN, draft; base `r1b/phase1a-smappservice-harness`; head `r1b/phase1b-sacrificial-observation` at the same SHA.
- Hosted workflow run `31820126234` completed successfully at the Phase 1B SHA: macOS 14 job `94831104637`; macOS 15 job `94831104674`.
- Protected visible checkout metadata remained `r1a/public-trust-surface` at `c9f88e3f81b255f39b41a6dd276b6ef35982d26a`; protected file existence was checked without reading its contents.

## Fresh non-live gates

Every command in this table exited zero. Before inserting the retirement fuse, the newly written retirement gate intentionally failed because that fuse was absent.

| Command | Fresh observed result |
|---|---|
| `desktidy-sort --self-test` | `PASS: 17 deterministic safety checks` |
| `desktidy-sort --r0-test` | `R0 CONTROLS: 31 passed, 0 failed` |
| `desktidy-sort --state-test` | `R1A GATES: 63 passed, 0 failed` |
| `desktidy-sort --phase1a-test` | `PHASE1A GATES: 64 passed, 0 failed` |
| `desktidy-sort --phase1a1-test` | `PHASE1A1 GATES: 24 passed, 0 failed` |
| `desktidy-sort --phase1b-test` | `PHASE1B GATES: 10 passed, 0 failed` |
| `scripts/test-phase1a-wiring.sh` | `phase1a-wiring: PASS`; planted poison detected |
| `scripts/test-phase1a1-public-boundary.sh` | `PHASE1A1 PUBLIC: 32 passed, 0 failed, 32 cases` |
| `scripts/test-phase1b-retirement.sh` | `phase1b-retirement: PASS` |

The continuation requires a Phase 1A.1 `42/42` reproduction, but the audited source at the mandated base reports `24/24`; its public-boundary runner separately reports `32/32`. This is an evidence/program count disagreement, not a converted pass.

## Reproduced current live-authority readback

Read-only `launchctl print gui/501/<label>` after the non-live gates returned:

| Label | Result |
|---|---|
| `com.desktidy.sort` | rc 113, absent |
| `com.desktidy.notify` | rc 113, absent |
| `com.desktidy.sacrificial` | rc 113, absent |
| `com.sicarii.desktop-autosort` | rc 0, loaded |
| `com.sicarii.desktop-autosort-notify` | rc 0, loaded |

This is current-state evidence only. It does not prove historical non-invocation.

## Source and transcript audit

The production ServiceManagement calls are isolated in `probe/SMAdapterProduction.swift`; the Phase 1B unit suite is explicitly fake/hermetic (`src/Phase1BTests.swift:3-5`) and its fresh result was 10/10. The historic observation document records a real register and unregister outcome, but its evidence is insufficient for the strict independent validation required by the continuation:

1. `docs/evidence/R1B_PHASE1B_SACRIFICIAL_OBSERVATION.md:27-38` and `:64-71` omit raw fields that the probe is designed to emit, including root/nonce and complete ledger values. They are not marked as excerpts.
2. The document has no committed raw durable pre-call transaction record, nonce-reservation record, authorization digest, authenticated event log, transcript schema, or validator. It cannot independently bind both operations to the same measured executable/source/plist/auth/nonce/transaction data.
3. The document records source commit `4725c5143af18a78df303eaaeb36c9221caedc04` (`R1B_PHASE1B_SACRIFICIAL_OBSERVATION.md:4`), while the audit base is `cbfb795…`. Git ancestry was verified: `4725c51` is the parent of `cbfb795`; the evidence commit added only `CHANGELOG.md` and the observation document. That chronology is coherent, but it does not repair the missing raw evidence.
4. The historical A→B→A record documents a static `--commit-mutation` source poison and a 10/10 suite (`R1B_PHASE1B_ABA_COMMIT_MUTATION_GATE.md:1-44`). The current Phase 1B suite does not execute a compiled probe default-stop subprocess; its B10 control is structural. This is insufficient as a runtime proof of the default-stop path, although it is useful regression coverage.
5. The runner formerly synthesized authorization JSON itself (`scripts/observe-phase1b.sh` before retirement), contradicting the runbook requirement that the architect create each authorization file (`docs/R1B_PHASE1B_OPERATOR_RUNBOOK.md:66-78`). The retirement fuse removes replay capability; it cannot retroactively make the original capability provenance independently verifiable.

The historical transcript is internally coherent and bounded: it records `status=enabled` plus a `launchctl` service record for `com.desktidy.sacrificial`, then `status=notRegistered` plus rc 113 absence, and it explicitly leaves Login Items and FDA/TCC unknown (`R1B_PHASE1B_SACRIFICIAL_OBSERVATION.md:40-84`). It must not be upgraded from this bounded historical assertion to independently validated lifecycle evidence.

## Phase A verdict

`PHASE1B_EVIDENCE_BLOCKED_INCOMPLETE_HISTORICAL_TRANSCRIPT`

The required `PHASE1B_EVIDENCE_ACCEPTED_FOR_BOUNDED_SEMANTICS` verdict is not supportable from the committed evidence. A new validator can prove that future transcripts contain all required fields and reject poisons, but cannot authenticate or reconstruct missing records from the one permitted lifecycle. Repeating the lifecycle is expressly unauthorized.

## Verified / believed / unknown

- **Verified:** starting identity; fresh non-live gate results above; present service-state readback; source-level Phase 1B fake test isolation; transcript/document contents; historical runner retirement behavior.
- **Believed only from the historical document:** the recorded real register/unregister calls, the original probe executable hash, status values, and historical pre/post personal-label readbacks.
- **Unknown:** Login Items pixels, FDA/TCC, reboot/login semantics, original authorization bytes/digests, original nonce reservations, original durable pre-call transaction records, original full untruncated process output, and an independent end-to-end runtime proof of the default-stop gate.

## Restart-safe continuation boundary

No real lifecycle replay is permitted. Continue only non-live product work on `r2/full-local-native-completion-omp` from this audit checkpoint. The first required follow-up is a validator/poison suite that fails closed for any future transcript missing the raw bindings listed above; it must not assert that this historic transcript is accepted. Terminal local-release success remains blocked until an architect separately authorizes a new bounded lifecycle with a complete evidence contract, or revises the terminal evidence requirement.
