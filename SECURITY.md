# Security Policy

## What DeskTidy can and cannot do

DeskTidy is designed so that its worst-case failure is a file in the wrong
folder — never data loss or data exposure:

- **No network access of any kind.** The binary makes no network calls; there is
  no telemetry, no update checker, no analytics. You can verify this from the
  source — it's under 800 lines total.
- **Never deletes.** The engine has no delete path for user files; moves are
  collision-safe (a name clash keeps both files).
- **AI is local and advisory.** The optional triage uses Apple's on-device
  model, receives only a bounded local preview, treats file content as
  untrusted input, and can only *write a suggestions file* — it has no ability
  to move, rename, or delete.
- **Scoped privilege.** Only the small signed `desktidy-sort` binary receives
  Full Disk Access — not bash, not a script another process could swap out.
- **Every action is logged** to `~/Library/Application Support/DeskTidy/desktidy.log`.

## Reporting a vulnerability

If you find a way to make DeskTidy delete data, act outside its target folder,
exfiltrate anything, or follow instructions embedded in file content, please
report it privately:

- Email: **sic.tau@pm.me**
- Or open a GitHub **private security advisory** on this repository.

Please include reproduction steps. You can expect an acknowledgment within
72 hours. Fixes for confirmed issues will be released as fast as practical and
credited to you unless you prefer otherwise.

## Supported versions

Only the latest release is supported with security fixes.
