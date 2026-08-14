# R1B Phase 1A A→B→A — second pre-call authority/target check

Semantic mutation of `src/MigrationTransaction.swift`: skip the second
pre-call evidence check so a foreign mover or invalid target appearing
between preflight and mutation is ignored.

No production ServiceManagement adapter invocation. Fake adapter only.

## A (green)

- file: `src/MigrationTransaction.swift`
- SHA-256: `007cef67d03bffce6ac3d5ead179078d7fae25fd6ac0f0eb3c2f9079e87eabc3`
- command: `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-phase1a-aba/desktidy-sort && /tmp/desktidy-r1b-phase1a-aba/desktidy-sort --phase1a-test`
- exit: `0`
- excerpt:

```
PASS  S11  transaction refused
PASS  S12  transaction refused
PHASE1A GATES: 64 passed, 0 failed
```

## B (second pre-call disabled)

- SHA-256: `f26672bde0cab8b77750c0fa53facb93d24913c4655af47d40f7d32320f2955e`
- rebuild after deleting the previous binary
- command: `--phase1a-test`
- exit: `1`
- failing IDs:

```
FAIL  S11  transaction refused — got indeterminate regs=1 unregs=0
FAIL  S12  transaction refused — got indeterminate regs=1 unregs=0
PHASE1A GATES: 62 passed, 2 failed
```

Intended reason: without the second check, `requestRegister` ran (`regs=1`)
after preflight had been clean. S11 plants a foreign mover at call time; S12
invalidates the target at call time.

Diff (B vs A):

```diff
-        if !skipSecondPreCallCheck {
+        if false && !skipSecondPreCallCheck { // B-MUTATION: skip second pre-call authority/target check
```

## Restore

- SHA-256: `007cef67d03bffce6ac3d5ead179078d7fae25fd6ac0f0eb3c2f9079e87eabc3` (equals A)
- `--phase1a-test` exit 0 — 64/64; S11 PASS
- `--self-test` 17/17; `--state-test` 63/63; `--r0-test` 31/31
