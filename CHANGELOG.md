# Changelog

## v1.0.0

First public release.

- Deterministic Desktop sorter (`desktidy-sort`): files loose items into
  Documents / Images / Screenshots / Videos / Audio / Archives / Code / Folders,
  with an Inbox fallback for anything it can't confidently place.
- Safety guarantees: never deletes; collision-safe moves (no overwrite);
  15s settle window; skips in-progress downloads; single-instance lock.
- Real-time notifications (`desktidy-notify.sh`): a macOS banner per move,
  **clickable** to reveal the file in Finder (via `terminal-notifier`, with a
  plain-banner fallback). Error banners break through Do Not Disturb.
- Optional on-device AI triage (macOS 26+ / Apple Intelligence): suggestions
  only, fully local; compiled out automatically on older macOS.
- `launchd` agents for hands-off operation that survives reboots.
- One-command `install.sh` / `uninstall.sh`. Retarget any folder with
  `--target`. Configure everything in `src/Config.swift`.

### Tested
- Deterministic routing, safety behaviors, and self-test: verified on
  macOS 26 (Apple Silicon), AI path included.
- The AI-excluded build path relies on Swift's `#if canImport(FoundationModels)`
  and has been reasoned through but not yet built on a pre-26 SDK — please open
  an issue if you hit a build problem on older macOS.
