# R1B Phase 0 A→B→A — duplicate native-config keys must fail closed

Semantic mutation of `src/NativeConfigParser.swift`: after JSON escape
decoding, a repeated object key is ignored instead of rejected.

No live Desktop paths, no private file contents.

## A (green)

- file: `src/NativeConfigParser.swift`
- SHA-256: `00efb21e99cce717f73fe812c879599b7087449a9b1a137bf037a23b96a02e5d`
- command: `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-dupe-aba/desktidy-sort && /tmp/desktidy-r1b-dupe-aba/desktidy-sort --state-test`
- exit: `0`
- excerpt:

```
PASS  D01  duplicate target keys (different values) → invalid
PASS  D04  escaped-equivalent duplicate target key → invalid
PASS  D08  engine refuses duplicate-key config (exit 3, no move)
R1A GATES: 63 passed, 0 failed
```

## B (duplicate rejection disabled)

- SHA-256: `713477b521b5173073bfe0bde57dc5a7cf3a05d0079efaa60519428b1217b644`
- rebuild: previous binary deleted, then `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-dupe-aba/desktidy-sort`
- command: `/tmp/desktidy-r1b-dupe-aba/desktidy-sort --state-test`
- exit: `1`
- failing IDs:

```
FAIL  D01  duplicate target keys (different values) → invalid — got pausedNotLoaded res=resolved src=nativeConfig target=.../target-b-...
FAIL  D02  duplicate target keys (identical values) → invalid — got pausedNotLoaded res=resolved
FAIL  D03  duplicate schema keys → invalid — got pausedNotLoaded
FAIL  D04  escaped-equivalent duplicate target key → invalid — got pausedNotLoaded target=.../target-b-...
FAIL  D08  engine refuses duplicate-key config (exit 3, no move) — exit=0 stayed=true
R1A GATES: 58 passed, 5 failed
```

D01/D04's intended reason is last-wins resolution (`res=resolved`, `nativeConfig`)
instead of `invalid`. D08's `exit=0` shows the engine accepted a selected
duplicate-key config and did not refuse movement.

Diff (B vs A):

```diff
             if seen.contains(key) {
-                return .failed("native config has a duplicate key")
-            }
+                // B-MUTATION: ignore duplicate keys after escape decoding
+            } else {
             seen.insert(key)
+            }
```

## Restore (A bytes)

- `cp` of the A snapshot over `src/NativeConfigParser.swift`
- SHA-256: `00efb21e99cce717f73fe812c879599b7087449a9b1a137bf037a23b96a02e5d` (equals A)
- rebuild after deleting the B binary
- `--state-test` exit 0 — `R1A GATES: 63 passed, 0 failed`; D01 PASS
- `--self-test` exit 0 — `PASS: 17 deterministic safety checks`
- `--r0-test` exit 0 — `R0 CONTROLS: 31 passed, 0 failed`
