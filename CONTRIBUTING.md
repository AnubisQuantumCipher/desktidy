# Contributing to DeskTidy

Thanks for wanting to help! DeskTidy is deliberately small (~700 lines of Swift
plus two shell scripts), and we'd like to keep it that way.

## Ground rules

1. **Safety invariants are non-negotiable.** Any change must preserve:
   - never delete a user file;
   - never overwrite on name collision;
   - never move a file before the settle window;
   - the AI layer never moves/renames/deletes anything;
   - no network access from any component.
2. **`--self-test` must pass** (`./build/desktidy-sort --self-test`). If you add
   routing rules, add self-test cases for them.
3. **CI must be green** on both the AI-compiled-in and compiled-out paths.

## Dev loop

```bash
# build
mkdir -p build
xcrun swiftc -O -parse-as-library src/*.swift -o build/desktidy-sort

# test without touching your real Desktop (env overrides)
SB=$(mktemp -d) APP=$(mktemp -d)
DESKTIDY_TARGET_DIR="$SB" DESKTIDY_APP_DIR="$APP" ./build/desktidy-sort --verbose

# safety checks
./build/desktidy-sort --self-test
```

**Always test against a sandbox target (`DESKTIDY_TARGET_DIR`), never your real
Desktop.** Ask us how we know.

## Good first contributions

- New extension mappings (with self-test cases)
- A JSON config loader so users don't need to rebuild to customize
- Localization of the notification strings
- The menu-bar app from the roadmap

## Style

Match the existing code. Prefer boring, readable Swift over clever Swift.
One feature per PR. Explain *why* in the PR description.
