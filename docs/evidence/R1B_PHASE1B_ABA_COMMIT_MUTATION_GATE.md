# R1B Phase 1B A→B→A — `--commit-mutation` stop gate

Semantic mutation of `probe/ProbeMain.swift`: drop the
`--commit-mutation` check so a sealed grant would proceed to adapter
construction without the second factor.

No observation command was run on the B tree. Fake/hermetic tests only.

## A (green)

- file: `probe/ProbeMain.swift`
- SHA-256: `95f1087d4b800129fb1e3906dfd247d41b980665c1a327b1683a3446f95755cc`
- command: `desktidy-sort --phase1b-test`
- exit: `0`
- excerpt:

```
PASS  B10  default path still stops before adapter without --commit-mutation
PHASE1B GATES: 10 passed, 0 failed
```

## B (gate removed)

- SHA-256: `491748a98edaa2ebb8d4d5413f41be4e1ad5c248007d8357e69ee75c33a27d21`
- command: `--phase1b-test`
- exit: `1`
- failing ID:

```
FAIL  B10  default path still stops before adapter without --commit-mutation
PHASE1B GATES: 9 passed, 1 failed
```

Diff (B vs A):

```diff
-                        if !args.contains("--commit-mutation") {
+                        if false { // B-MUTATION: drop commit-mutation gate
```

## Restore

- SHA-256: `95f1087d4b800129fb1e3906dfd247d41b980665c1a327b1683a3446f95755cc` (equals A)
- `--phase1b-test` exit 0 — 10/10; B10 PASS
