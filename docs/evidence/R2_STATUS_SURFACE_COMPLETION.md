# DeskTidy R2 — native status surface completion receipt

Date: 2026-08-15
Implementation checkpoint: `38ecf39939496851a81eb72596c0a9baf3d5ec81`
Branch: `r2/full-local-native-completion-omp`
PR: <https://github.com/AnubisQuantumCipher/desktidy/pull/6>

## Completed implementation

- The production `MenuBarExtra` now renders durable pause state separately from
  agent-loaded state. An unloaded agent is `Not running`, while durable pause
  uses `pause.circle.fill` and `Paused — file movement is disabled`.
- Onboarding no longer exposes a misleading Pause action.
- Healthy state exposes guarded `Tidy Now`, `Pause`, and eligible `Undo`
  controls through `CanonicalApplicationCore`; adverse states expose no movement
  controls.
- Action results refresh the visible state and history without exposing receipt
  identifiers as user-facing errors.
- Validated undo receipts render as `Restored` at the target root. The root-level
  exception rejects nested, traversal, and symlink destinations.
- `--ui-preview` renders the exact shared `NativeMenuContent` in a deterministic
  ordinary window for fixture-only pixels and AX inspection. Normal launch
  remains a window-style `MenuBarExtra`.
- The canonical gate inventory now contains 45 records, including required
  executable gate `native-status-surface`.
- Hosted CI launches and captures the built native surface on macOS 14 and 15.

## Direct operation evidence

All paths were under `/private/tmp/desktidy-visual-*`; the live Desktop was not a
movement target.

- Tidy Now moved `invoice.pdf` to `Documents/invoice.pdf`.
- Undo restored the original root path and removed the categorized destination.
- Both observations produced SHA-256
  `a842ff97b17be0ff9ca00c7198ba3efe30365ab19c5203a9234f4a2e34f82115`.
- Pause wrote a valid `pausedIndefinitely` durable state; Resume returned the
  durable mode to `running`.
- Pixels/AX controls were directly observed for onboarding, healthy, populated
  history, restored history, paused, long foreign conflict, light ambiguous,
  and high-contrast degraded-ledger states.
- The normal non-preview interactive launch added a tray icon to the real macOS
  menu bar; terminating that exact fixture process removed it.

In-tree fixture capture:
`docs/evidence/assets/R2_PHASE_N_STATUS_SURFACE.png`

SHA-256:
`487d1e8d9fb714815ebf0bb028d7909f6f2e73c8fdd482995f8a91b8fbb25936`

## Focused gates

- Phase 1A migration/adapter/interlock: 64 passed, 0 failed.
- R1A state/UI policy: 72 passed, 0 failed.
- Phase H history/undo: 7 passed, 0 failed.
- Swift CLI and app builds: warnings promoted to errors, 0 warnings.
- Claims scanner: 23 files, 5 rules, 0 active matches.
- Native surface harness: window observed, PNG captured and hashed, process
  cleanup observed; overwrite control returned exit 2.

## Canonical and clean-clone proof

Committed-worktree summary:
`/private/tmp/desktidy-status-full-local-38ecf39.json`

Summary SHA-256:
`e206b7cf582501d4ee8b173b29c41a37e22b027309d572125726245c3466f97f`

Clean-clone summary:
`/private/tmp/desktidy-status-final-clone-summary-38ecf39.json`

Summary SHA-256:
`2497f4110a9d51ef13b7f780ca43e714d6657a0a6412631e180173b69634c613`

Both independent validations returned:

- 45 records;
- 39 passed;
- 0 failed;
- 3 indeterminate;
- 3 blocked;
- `native-status-surface`: passed;
- overall: blocked, because every record must pass for success.

The clean clone was
`/private/tmp/desktidy-status-final-clone.9KwDAr` at exact checkpoint
`38ecf39939496851a81eb72596c0a9baf3d5ec81`.

## Website proof

From that exact clean clone:

- `npm ci`: completed from `package-lock.json`;
- `npm audit --audit-level=high`: 0 vulnerabilities;
- `npm run build`: passed, including TypeScript;
- `npm run lint`: passed.

Visible non-fatal warnings:

- Next.js Edge Runtime is deprecated;
- an Edge page disables static generation for that page;
- `unrs-resolver@1.12.2` postinstall remained blocked by npm's `allowScripts`
  policy; it was not approved to manufacture a green build.

## Hosted exact-SHA proof

Run: <https://github.com/AnubisQuantumCipher/desktidy/actions/runs/31867012168>

Run ID: `31867012168`

- exact head: `38ecf39939496851a81eb72596c0a9baf3d5ec81`;
- macOS 14: passed;
- macOS 15: passed;
- `Native status surface launches and captures`: passed in both jobs;
- CodeRabbit: passed;
- PR merge state at observation: `CLEAN`, draft.

Downloaded run-metadata SHA-256:
`ef0e855cd47e5e58031fa1d9d8bbe1f818a324da463f5861044c6716358f8d32`

## Local RC artifact

Clean-clone RC:
`/private/tmp/desktidy-full-local-release-z4inbjab/dist/DeskTidy-local-rc-arm64-macos14.zip`

Archive SHA-256:
`7e4af4d967b12dada048d9ed8f144359cd9e1c66f84233792211d44ac63cbf8b`

Manifest SHA-256:
`96e31cdee4c58e98b4e09c601d05f841a428a8e698e39eb9583fc1c1aa81d96e`

The manifest binds the implementation checkpoint, arm64, macOS 14 minimum,
ad-hoc local-only signing, successful signature verification, and no
notarization. Independent RC verification passed manifest, signature, and fresh
fixture smoke. Gatekeeper rejected the ad-hoc artifact as recorded; that is not
represented as public distribution readiness.

## Live-state reconciliation

Observed after fixture cleanup:

- `com.sicarii.desktop-autosort`: loaded, exited normally, last exit code 0;
- `com.sicarii.desktop-autosort-notify`: loaded and running;
- `com.desktidy.sort`: absent;
- `com.desktidy.notify`: absent;
- `com.desktidy.sacrificial`: absent;
- no DeskTidy fixture process remained;
- surviving OMP processes owned Anubis and JACKAL worktrees, not DeskTidy;
- local and remote implementation checkpoint matched.

No personal agent was unloaded, restarted, rewritten, or replaced.

## Residuals retained

1. `phase1b-evidence` is indeterminate: the historical raw lifecycle transcript
   is not reproducible.
2. `visual-accessibility` remains indeterminate: direct surface pixels and AX
   controls now exist, but keyboard focus-ring traversal and spoken VoiceOver
   output were not observed. Host Full Keyboard Access was not changed.
3. `sacrificial-lifecycle` remains blocked: direct install/upgrade/uninstall was
   not repeated.
4. `live-authority-readback` remains indeterminate inside the canonical runner;
   the separate read-only baseline above identifies the live personal services.
5. `website-build` and `hosted-final-sha` remain static blocked placeholders in
   the canonical runner; the detached clean-clone and exact-SHA proofs above do
   not silently rewrite those gate meanings.
6. Developer ID signing, notarization, TestFlight, App Store publication, and a
   public installer remain blocked by distribution credentials/account state.
7. The PR remains draft and unmerged. Merge is an architect trust-surface
   decision, not an automatic consequence of green bounded gates.

## Bounded verdict

The native status-bar product surface, guarded Tidy/Undo/Pause controls,
fixture-bound visuals, app packaging, website, exact-SHA hosted CI, and
clean-clone canonical executable gates have no observed failure at the
implementation checkpoint. Full distribution, direct lifecycle replay,
keyboard/VoiceOver completion, and merge are not sealed and remain explicitly
open.
