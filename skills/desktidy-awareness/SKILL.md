---
name: desktidy-awareness
description: Use when working in the DeskTidy repository and a task might assume a DeskTidy service is active on a Desktop or other folder.
---

# DeskTidy repository boundary

The repository contains an ad-hoc local deployment. The 2026-08-15 deployment
receipt records `com.desktidy.sort` and `com.desktidy.notify` as the sole active
Desktop services on the operator Mac, with the former personal-sorter labels
and active plists absent. Runtime state can drift, so re-probe before acting.

## Rules

1. Do not assume a missing Desktop file was moved by DeskTidy. Inspect the
   applicable environment or evidence before assigning a cause.
2. Do not invoke `desktidy setup`, `desktidy teardown`, `launchctl` mutation,
   `SMAppService` registration, or Desktop-targeted movement without explicit
   authorization. Never load the former sorter while `com.desktidy.sort` owns
   the Desktop; two Desktop authorities are prohibited.
3. Treat receipt chains as unkeyed integrity evidence, not authentication.
4. Suggestions are non-mutating. They cannot authorize a move, rename, delete,
   or upload action.
5. Retained former-sorter files and rollback plists are inactive recovery
   assets, not authorization to bootstrap them.
6. The only authorized live canary was completed and removed. Use disposable
   `/private/tmp` roots unless a new exact Desktop canary is explicitly approved.
