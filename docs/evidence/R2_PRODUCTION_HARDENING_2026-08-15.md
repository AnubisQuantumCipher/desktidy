# DeskTidy R2 production hardening receipt

Date: 2026-08-15

Repository branch: `r2/full-local-native-completion-omp`

Code-and-gate checkpoint: `585f5ad33657c423bf718c32177f2d3f7ceb9879`

This receipt extends, but does not replace, the local deployment boundary in
`R2_LOCAL_PRODUCTION_DEPLOYMENT.md`. It records a production-focused security,
reliability, website, and truth-surface pass. It is not a public release or a
Developer ID/notarization claim.

## Security result and remediation

Standard scan `b9c58662-f549-4e74-9edc-146a41cc8809` reviewed all 157 tracked
files at pre-fix commit `56a29682aa4c660f9a4f32db2e032a60a3da11f7`
across six threat surfaces. It reported one medium-confidence-boundary finding:
the production movement lock opened a current-user-writable path without
`O_NOFOLLOW` before `fchmod` and `flock`.

The finding was fixed at `c707cf02ab58a2b6735be7d0db9b5ad58ef9f673`.
`MovementProcessLock` now opens with `O_NOFOLLOW | O_CLOEXEC`, verifies a
current-user-owned regular file with one hard link, then applies mode `0600`
and acquires the lock. Phase G control G15 plants a symbolic link and proves
the target bytes and permissions remain unchanged. Phase G is 15 passed, zero
failed.

Sealed scan artifacts (local workbench):

| Artifact | SHA-256 |
|---|---|
| `scan-manifest.json` | `ed5e43b0037d9f98eecd3679c0cba5fe13338b9cb7a13cb237503299daa76f54` |
| `findings.json` | `2c82af0d6601b5fc799dfd7a3bad1a64d4cbd654b9d1e75a68f6b5a3c06cbf63` |
| `coverage.json` | `66da70060a9956db9d7aed174e8176028dba96a3dd0cd4862a006bb279e5711a` |
| `report.md` | `b7a34fcf67cf131d9e3464b8f23b5bcb3ae3b1d5262096934f5c7f14c22c8118` |
| `results.sarif` | `0e67ef9d6eec68c345721bc880be89fab85e831c284998332e483d742c68083e` |

The scan used the documented single-agent fallback because the controlling
contract prohibited parallel writers or investigators on this worktree.

## Reliability and public-surface changes

- The legacy source installer builds, signs, self-tests, and authority-checks
  an isolated staged candidate before replacing a live executable. A failed
  candidate therefore cannot corrupt the installed movement binary.
- The inactive waitlist form, write API, Neon database dependency, and six
  unused marketing/demo components were removed. The website now statically
  emits only `/`, `/privacy`, `/robots.txt`, and `/sitemap.xml`.
- Website privacy, positioning, verification, design, backlog, release, and
  security wording now match the bounded local-deployment claim. The claim
  scanner covers the current privacy and website README surfaces.
- The canonical gate now executes the locked website install, lint, production
  build, and high-severity dependency audit. It also performs a read-only live
  authority check requiring both DeskTidy labels, both former labels absent,
  and the exact Desktop target.

## Exact verification

Canonical summary:
`/private/tmp/desktidy-production-polish-canonical-585f5ad.json`

SHA-256:
`adcf05a3e2b7745d998273c6c15c3a08040bef829ceacef8377072fada8f943a`

The independent validator accepted all 46 rows. Result: 42 passed, two
indeterminate, two blocked, zero failed. The four non-passing rows preserve
existing claim boundaries: historical Phase 1B evidence, complete
keyboard/VoiceOver acceptance, direct sacrificial lifecycle, and hosted CI at
the instant the local summary was created. They do not invalidate the bounded
local deployment result.

Hosted CI run
[`31878333906`](https://github.com/AnubisQuantumCipher/desktidy/actions/runs/31878333906)
then passed the exact `585f5ad33657c423bf718c32177f2d3f7ceb9879`
checkpoint on macOS 14 and macOS 15.

PR 6 remained open, ready, mergeable, and unmerged after the checkpoint push.
No legacy sorter was loaded, no second Desktop authority was introduced, and
no new live Desktop canary was created.

## Verdict

**COMPLETE for this production-hardening extension of the authorized local
deployment.** Public Developer ID signing, notarization, public native
distribution, complete keyboard/VoiceOver acceptance, and reboot/login
evidence remain separate gates and are not claimed here.
