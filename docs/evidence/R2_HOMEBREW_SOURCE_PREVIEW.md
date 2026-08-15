# R2 Homebrew source-preview evidence — 2026-08-15

## Claim boundary

This receipt proves a public, source-built Homebrew developer-preview lane. It
does not claim Developer ID signing, notarization, a prebuilt cask, App Store
readiness, or supported public-production distribution.

The preview formula installs app bytes only. It does not call `launchctl`,
register an `SMAppService`, replace a plist, or load a second Desktop mover.

## Published bindings

| Surface | Exact binding |
|---|---|
| DeskTidy source tag | `v1.2.0-preview.1` |
| DeskTidy source commit | `19355ff83c610fb4251af2bc593d0460c3e894eb` |
| GitHub tag archive SHA-256 | `847789b256ca51425aa28bf2d7e4bdee97dbbc758cf17da2b667d54fdb49a9ba` |
| Tap commit | `504f157f9ef48d19d24b18730f8d0e7e35a17a78` |
| Formula | `anubisquantumcipher/tap/desktidy-r2-preview` |
| Formula version | `1.2.0-preview.1` |

The tap also disables the old `desktidy` formula with the reason that it
installs the retired legacy Desktop authority.

## Formula verification

The published formula passed:

- `brew style` for both the preview and disabled legacy formula;
- `brew audit --strict --online --formula`;
- a real source download from the tagged GitHub archive;
- local app compilation through `scripts/build-app.sh`;
- `brew test`, including exact `sourceCommit` JSON equality and strict deep
  code-signature verification;
- `brew info`, which reported version `1.2.0-preview.1`, Apple silicon, and
  macOS 14 or newer.

The installed preview reported bundle identifier `com.desktidy.app`,
`Signature=adhoc`, no Team ID, and source commit
`19355ff83c610fb4251af2bc593d0460c3e894eb`.

## Authority invariants across install and uninstall

Read-only `launchctl print` and plist observations before installation, after
installation/test, and after uninstall agreed:

| Authority surface | Result at all three observations |
|---|---|
| `com.desktidy.sort` | loaded |
| `com.desktidy.notify` | loaded |
| `com.sicarii.desktop-autosort` | absent |
| `com.sicarii.desktop-autosort-notify` | absent |
| legacy sorter plist | absent |
| legacy notifier plist | absent |

The test did not launch the preview UI, create a Desktop canary, or mutate the
live target. The test formula was uninstalled after verification; the existing
native DeskTidy authority remained unchanged.
