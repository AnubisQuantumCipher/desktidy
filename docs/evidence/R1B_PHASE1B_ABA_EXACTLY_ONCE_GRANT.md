# R1B Phase 1B A→B→A — exactly-once sealed-grant dispatch

Semantic mutation of `src/GrantedMutation.swift`: drop `O_EXCL` so a
prepared grant can be dispatched twice against the same nonce.

No live ServiceManagement registration. Fake/hermetic roots only.

## A (green)

- file: `src/GrantedMutation.swift`
- SHA-256: `04ab3b4aa252cb16f535d95e136d5ead1b32a01eca2c73ccf277112d25803644`
- command: `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-p1b-aba-36284/desktidy-sort-A && /tmp/desktidy-p1b-aba-36284/desktidy-sort-A --phase1b-test`
- exit: `0`
- excerpt:

```
PASS  B11  nonce/grant replay refused on second dispatch
PHASE1B GATES: 25 passed, 0 failed
```

## B (O_EXCL removed)

- SHA-256: `d335d6f5df9251541e9d20d7c96e3fee3737787ee297cfb0f23f43768d04c644`
- rebuild after deleting the previous B binary
- command: `--phase1b-test`
- exit: `1`
- failing IDs:

```
FAIL  B11  nonce/grant replay refused on second dispatch — first=invoked(main.SMAdapterStatus.enabled) second=invoked(main.SMAdapterStatus.enabled)
PHASE1B GATES: 24 passed, 1 failed
```

Intended reason: without `O_CREAT|O_EXCL`, the second dispatch of
`nonce-1b11` overwrites the consume-once marker instead of refusing, so
the fake adapter registers twice.

Diff (B vs A):

```diff
-        let flags = disableExactlyOnceForMutationTest
-            ? (O_CREAT | O_WRONLY)
-            : (O_CREAT | O_EXCL | O_WRONLY)
+        let flags = (O_CREAT | O_WRONLY) // B-MUTATION: drop O_EXCL so grant replay can pass
```

The test hook `disableExactlyOnceForMutationTest` is reset to `false` by
`Phase1BTests.runAll()`. Mutating only that default is not load-bearing;
the B mutation therefore changes the open flags themselves.

## Restore

- SHA-256: `04ab3b4aa252cb16f535d95e136d5ead1b32a01eca2c73ccf277112d25803644` (equals A)
- `--phase1b-test` exit 0 — 25/25; B11 PASS
