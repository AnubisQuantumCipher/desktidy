# DeskTidy website source — status boundary

Date: 2026-08-15

This file replaces a historical website verification report that described an
older product state and deployment. It must not be used as evidence for a
current public website, installer, waitlist, CI result, or release.

## Current source statement

- `website/` is repository source only. This phase did not deploy it.
- The website source now directs readers to the repository's local-RC evidence
  instead of presenting a Homebrew installation or public product availability.
- The current DeskTidy artifact is an ad-hoc arm64 macOS 14+ local RC built and
  tested on fixture roots. It is not Developer ID signed, notarized, or
  Gatekeeper-accepted public distribution.
- Native visual/accessibility evidence is indeterminate. Live Desktop,
  ServiceManagement, Login Items, FDA/TCC, reboot/login, and no-network binary
  audit results are not established by this website source.

## Historical report boundary

Any prior deployment URL, production alias, environment variable, waitlist,
performance, accessibility, visual, SEO, or browser result in repository
history is historical context only. Reproduce it independently before treating
it as current evidence.
