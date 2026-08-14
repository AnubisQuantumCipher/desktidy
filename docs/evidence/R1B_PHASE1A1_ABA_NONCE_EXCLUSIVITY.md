# R1B Phase 1A.1 A→B→A — durable nonce exclusivity

Semantic mutation of `src/DurableNonceStore.swift`: drop `O_EXCL` so a
replay or concurrent duplicate can open the same reservation path.

No production ServiceManagement adapter invocation. Fake/hermetic roots only.

## A (green)

- file: `src/DurableNonceStore.swift`
- SHA-256: `6200ce12ae8fd1e2d4cab5c0244a739acc657321d82ff32b22e3338457563bd1`
- command: `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-phase1a1-aba/desktidy-sort-A && /tmp/desktidy-r1b-phase1a1-aba/desktidy-sort-A --phase1a1-test`
- exit: `0`
- excerpt:

```
PASS  E08  nonce replay across store instances refused
PASS  E09  concurrent nonce reservation has exactly one winner
PASS  S11  retained second-precall foreign ID still refused at prepare
PASS  S12  retained second-precall target-change ID still refused
PHASE1A1 GATES: 24 passed, 0 failed
```

## B (O_EXCL removed)

- SHA-256: `fba4f0ba4ec0ace5bc09c13262d4d9ed268f0ce63323e0ce41e0cec635962a54`
- rebuild after deleting the previous B binary
- command: `--phase1a1-test`
- exit: `1`
- failing IDs:

```
FAIL  E08  nonce replay across store instances refused — reserved(...)
FAIL  E09  concurrent nonce reservation has exactly one winner — wins=8 losses=0
PHASE1A1 GATES: 22 passed, 2 failed
```

Intended reason: without `O_CREAT|O_EXCL`, the second reservation of
`nonce-rep1` overwrites instead of refusing, and all eight concurrent
openers of `nonce-race1` win.

Diff (B vs A):

```diff
-        let flags = disableExclusivityForMutationTest ? (O_CREAT | O_WRONLY) : (O_CREAT | O_EXCL | O_WRONLY)
+        let flags = (O_CREAT | O_WRONLY) // B-MUTATION: drop O_EXCL so replay/concurrent can pass
```

The test hook `disableExclusivityForMutationTest` is reset to `false` by
`Phase1A1Tests.runAll()`. Mutating only that default is not load-bearing;
the B mutation therefore changes the open flags themselves.

## Restore

- SHA-256: `6200ce12ae8fd1e2d4cab5c0244a739acc657321d82ff32b22e3338457563bd1` (equals A)
- `--phase1a1-test` exit 0 — 24/24; E08/E09/S11/S12 PASS

Retained second-precall transcript: `docs/evidence/R1B_PHASE1A_ABA_SECOND_PRECALL.md`.
S11/S12 re-run on this restore: PASS (phase1a 64/64 and phase1a1 24/24).
