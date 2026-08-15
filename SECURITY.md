# Security Policy

## Scope and release boundary

DeskTidy is presently an ad-hoc, local Apple Silicon macOS 14+ release
candidate. It is not Developer ID signed, notarized, publicly released, or a
supported native Homebrew distribution. The operator-Mac deployment and named
canary establish only the bounded local evidence recorded in
`docs/evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md`; they do not establish
reboot/login behavior, public-distribution safety, or a no-network binary audit.

The repository's fixture contracts exercise a guarded movement core. Their
model is intentionally narrow:

- movement is confined to the selected root and collision handling preserves
  the existing destination entry;
- receipts are append-only JSONL with an **unkeyed** SHA-256 chain; they are
  integrity evidence, not authentication;
- malformed, foreign, ambiguous, and unavailable authority inputs refuse;
- optional suggestions have no authority to move, rename, delete, upload, or
  otherwise mutate files.
- movement lock files are opened no-follow and verified as single-link regular
  files owned by the current user before permissions or locking are applied.

These are source/fixture boundaries, not a promise about an installed public
product. A no-network binary audit has not been recorded for this RC. Future
update checks are absent from this RC.

## Reporting a vulnerability

For a reproducible vulnerability in this repository, report privately to
**sic.tau@pm.me**. Include the affected commit, macOS version, reproduction
steps, and any proof-of-concept needed to reproduce the behavior. Do not post
sensitive exploit details in a public issue before maintainer coordination.

## Supported versions

There is no supported public DeskTidy release at this time. Security fixes and
release support have not been committed for a distributed artifact.
