# DeskTidy snippet for coding agents

## DeskTidy repository boundary

This repository's current DeskTidy artifact is an ad-hoc local release
candidate tested only with disposable fixture roots. It is not a public
installer and must not be assumed to be active on the operator's Desktop or
any other folder.

- Do not infer that a file moved because of DeskTidy. Inspect the exact local
  environment and evidence first.
- Do not run `desktidy setup`, `desktidy teardown`, service registration, or
  Desktop-targeted commands without explicit authorization.
- Suggestions are non-mutating and never authorize a file move.
- If a real mover is active on the machine, follow that mover's own documented
  policy; it is outside this repository's RC evidence.
