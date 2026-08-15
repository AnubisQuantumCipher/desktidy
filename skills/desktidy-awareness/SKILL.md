---
name: desktidy-awareness
description: Use when working in the DeskTidy repository and a task might assume a DeskTidy service is active on a Desktop or other folder.
---

# DeskTidy repository boundary

The repository currently contains an ad-hoc local release candidate verified
only with disposable fixture roots. It does **not** establish that DeskTidy is
installed, running, permitted, or registered on this Mac.

## Rules

1. Do not assume a missing Desktop file was moved by DeskTidy. Inspect the
   applicable environment or evidence before assigning a cause.
2. Do not invoke `desktidy setup`, `desktidy teardown`, `launchctl` mutation,
   `SMAppService` registration, or Desktop-targeted movement without explicit
   authorization.
3. Treat receipt chains as unkeyed integrity evidence, not authentication.
4. Suggestions are non-mutating. They cannot authorize a move, rename, delete,
   or upload action.
5. A separately installed personal mover is outside this repository's local-RC
   evidence. Follow its own policy rather than this skill.
