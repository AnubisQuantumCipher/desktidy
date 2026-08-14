# R1B Phase 0 A→B→A — malformed native config must not fall through

Semantic mutation of `src/TargetResolver.swift`: invalid native `config.json`
falls through to env/plist/default instead of failing closed.

No live Desktop paths, no private file contents.

## A (green)

- file: `src/TargetResolver.swift`
- SHA-256: `f84821ab5a8b0a6fc302f9d695bb53fd7c88a6d5d7ae5762e509f33d6111c619`
- command: `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-phase0-aba/desktidy-sort && /tmp/desktidy-r1b-phase0-aba/desktidy-sort --state-test`
- exit: `0`
- excerpt:

```
PASS  T01  malformed native config refuses instead of env/default fallback
R1A GATES: 55 passed, 0 failed
```

## B (semantic fail-open)

Mutation: if native config exists but `readNativeConfig` fails, `break` and
continue to plist/env/default.

- SHA-256: `aa6c1e278563c177b1580a1b6779527eaea219d73f125da958268cb6267f2436`
- rebuild: previous binary deleted, then `xcrun swiftc -O -parse-as-library src/*.swift -o /tmp/desktidy-r1b-phase0-aba/desktidy-sort`
- command: `/tmp/desktidy-r1b-phase0-aba/desktidy-sort --state-test`
- exit: `1`
- failing IDs:

```
FAIL  T01  malformed native config refuses instead of env/default fallback — got pausedNotLoaded res=resolved: no conflicting authority, and DeskTidy's agent is not loaded
FAIL  T06  empty/wrong-type native target refuses — empty=pausedNotLoaded wrong=pausedNotLoaded
FAIL  T07  unreadable native config refuses — got pausedNotLoaded: no conflicting authority, and DeskTidy's agent is not loaded
FAIL  T10  engine refuses ambiguous target (exit 3, no move) — exit=0 stayed=false
R1A GATES: 51 passed, 4 failed
```

T01's intended reason is env fallback (`pausedNotLoaded` / `res=resolved`).
T10's `exit=0 stayed=false` shows the engine moved the fixture witness after
the invalid config was ignored.

Diff (B vs A):

```diff
         if fm.fileExists(atPath: configURL.path) {
-            return finish(readNativeConfig(configURL, fm: fm), source: .nativeConfig, fm: fm)
+            let parsed = readNativeConfig(configURL, fm: fm)
+            switch parsed {
+            case .ok:
+                return finish(parsed, source: .nativeConfig, fm: fm)
+            case .failed:
+                break // B-MUTATION: fall through instead of fail-closed
+            }
         }
```

## Restore (A bytes)

- `cp` of the A snapshot over `src/TargetResolver.swift`
- SHA-256: `f84821ab5a8b0a6fc302f9d695bb53fd7c88a6d5d7ae5762e509f33d6111c619` (equals A)
- rebuild after deleting the B binary
- `--state-test` exit 0 — `R1A GATES: 55 passed, 0 failed`; T01 PASS
- `--self-test` exit 0 — `PASS: 17 deterministic safety checks`
- `--r0-test` exit 0 — `R0 CONTROLS: 31 passed, 0 failed`
