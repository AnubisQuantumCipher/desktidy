# DeskTidy R2 Hermes takeover and clean-clone reseal

Date: 2026-08-15
Branch: `r2/full-local-native-completion-omp`
Source checkpoint under test: `333be039c5daf8f3b1a70751f33bcb2c0c4e2c23`
Draft PR: <https://github.com/AnubisQuantumCipher/desktidy/pull/6>

## Takeover

- The visible OMP terminal reported `DESKTIDY_OMP_CONTINUATION_REQUIRED` and identified the denied push as the next command.
- OMP was exited from that terminal before repository mutation.
- The target worktree `/private/tmp/desktidy-omp-full-local-20260814-cbfb795` was clean at `333be039c5daf8f3b1a70751f33bcb2c0c4e2c23` and 25 commits ahead of the remote checkpoint `d855c662405f6a745401d34efb62b0a0d526940d`.
- The branch was fast-forward pushed. Local and remote then both resolved to `333be039c5daf8f3b1a70751f33bcb2c0c4e2c23`.
- No merge, release publication, live Desktop file access, service registration, or personal-mover mutation occurred.

## Exact-SHA hosted CI

GitHub Actions run: <https://github.com/AnubisQuantumCipher/desktidy/actions/runs/31864111010>

- `build-and-test (macos-14)`: passed, including all 16 recorded job steps.
- `build-and-test (macos-15)`: passed, including all 16 recorded job steps.
- Run head SHA: `333be039c5daf8f3b1a70751f33bcb2c0c4e2c23`.

The run emitted one infrastructure annotation: `actions/checkout@v4` targets deprecated Node.js 20 and was forced to Node.js 24. This did not fail either lane.

## Clean-clone canonical gate

A new single-branch clone was created from the public remote and checked clean at the source checkpoint. The repository-owned command was run:

```text
python3 scripts/run-full-local-release-gate.py \
  --root . \
  --output /private/tmp/desktidy-clean-reseal-summary-20260815.json
```

The independent validator was then run against the repository gate specification and that summary.

Observed result:

```text
source_commit=333be039c5daf8f3b1a70751f33bcb2c0c4e2c23
overall=blocked
passed=38
failed=0
blocked=3
indeterminate=3
gate_exit=2
validator_exit=0
validator=valid gates=44
```

Summary SHA-256: `31ac1ee37018f67564961165fe6d63daacd4756c4ded41d51717b93ef1e4e821`

The six non-pass records remained visible:

- `phase1b-evidence`: indeterminate; the historical raw lifecycle is not reproducible.
- `visual-accessibility`: indeterminate; no attributable native menu pixels or AX tree were obtained.
- `sacrificial-lifecycle`: blocked; direct install/upgrade/uninstall was not repeated.
- `live-authority-readback`: indeterminate in the canonical runner; a separate fresh read-only baseline confirmed the personal sorter and notifier remained loaded.
- `website-build`: blocked in the canonical runner because dependencies were absent at gate start; the detached clean-clone build below subsequently passed.
- `hosted-final-sha`: blocked by the runner's static placeholder; the detached exact-SHA CI run above subsequently passed.

No acceptance condition was silently changed to convert detached evidence into a canonical `passed` record.

## Detached website verification

From the same clean clone, with the checked-in lockfile:

```text
npm ci
npm run build
npm run lint
```

Observed:

- 360 packages installed; audit reported 0 vulnerabilities.
- Next.js 16.3.0 production compilation and TypeScript completed successfully.
- Six static-generation tasks completed; routes `/`, `/_not-found`, `/privacy`, `/robots.txt`, and `/sitemap.xml` were static, while `/api/waitlist` remained dynamic.
- ESLint exited successfully.
- `package-lock.json` SHA-256: `09d91cca52ca5c0088d872d8e1066d4ab9be7637b6ef6f08bf1387749fa11a34`.
- Build log SHA-256: `b43185296c037e34ec8a883d2731bd809bf74b65b30682d52ebc1d661298bd49`.
- Lint log SHA-256: `604a53930b583e15a8e6ccbf1a35ad37189741d875b24b975132959539c79a21`.

Non-fatal warnings remain visible: Next.js reports Edge Runtime deprecation and that an edge-runtime page disables static generation. npm also reported a blocked `unrs-resolver` postinstall script; build and lint still passed without approving it.

## Process and authority reconciliation

- An orphaned `/private/tmp/desktidy-phase-d-app/.../DeskTidy --smoke` process had survived for about eight hours even though current source makes `--smoke` exit before constructing the menu scene. It was terminated; the current hermetic smoke gates passed independently.
- A final clean-clone fixture app was launched with target, agents, application-support, and launchd-state paths entirely below `/private/tmp`. It exposed no ordinary window or attributable app-registry handle, and the desktop driver cannot capture a whole macOS display. The visual lane therefore remains indeterminate. The fixture process was stopped.
- `com.sicarii.desktop-autosort` remained loaded, pointed at `/Users/sicarii/Desktop`, and reported last exit code `0`.
- `com.sicarii.desktop-autosort-notify` remained loaded and running.
- No `com.desktidy.sort`, `com.desktidy.notify`, or `com.desktidy.sacrificial` launchd authority was introduced.

## Verdict

The pushed source checkpoint has no observed failing local canonical gate, hosted macOS lane, website production build, or website lint gate. The repository is **not** universally sealed: historical Phase 1B evidence, visual/AX evidence, and direct lifecycle evidence remain intentionally open, and canonical admission of detached exact-SHA CI/website evidence requires an explicit trust-surface design rather than a prose promotion.
