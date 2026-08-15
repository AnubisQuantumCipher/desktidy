# DeskTidy snippet for coding agents

## DeskTidy repository boundary

This repository's DeskTidy artifact is an ad-hoc local deployment, not a public
installer. The 2026-08-15 receipt records `com.desktidy.sort` and
`com.desktidy.notify` as the sole active services for the operator Desktop, but
runtime state must always be re-probed before action.

- Do not infer that a file moved because of DeskTidy. Inspect the exact local
  environment and evidence first.
- Do not run `desktidy setup`, `desktidy teardown`, service registration, or
  Desktop-targeted commands without explicit authorization.
- Never bootstrap the retained former sorter while `com.desktidy.sort` owns the
  Desktop. Two movement authorities for one root are prohibited.
- Suggestions are non-mutating and never authorize a file move.
- Retained former-sorter files/plists are rollback assets, not active authority.
- Use `/private/tmp` fixtures unless a new exact live canary is explicitly
  authorized; the completed production canary was removed after evidence.
