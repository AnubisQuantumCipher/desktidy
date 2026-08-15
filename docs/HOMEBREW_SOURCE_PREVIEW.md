# Homebrew source-built preview boundary

DeskTidy cannot responsibly ship its current ad-hoc-signed native app as a
normal Homebrew cask. A downloaded cask is quarantined by macOS, while an
ad-hoc signature is not a Developer ID identity and cannot be notarized. The
user would have to bypass Gatekeeper, which is outside the supported product
boundary.

The interim Homebrew lane is therefore a **source-built developer preview** in
the project tap, not a cask and not a public-production claim:

- Homebrew verifies the tagged source archive SHA-256 before building.
- The formula passes the exact tag commit as `DESKTIDY_SOURCE_COMMIT`.
- `scripts/build-app.sh` accepts that identity only for a source archive with
  no Git metadata. In a Git checkout, an override must equal clean `HEAD`.
- The resulting app remains ad-hoc signed and local-only.
- Installation must not register, bootstrap, replace, or unload any background
  service. It only installs the app and a launcher; lifecycle changes remain a
  separate, explicit, authority-checked operation.
- It must never tell users to disable Gatekeeper or install with
  `--no-quarantine`.

## Install the exact tagged preview

```bash
brew trust --formula anubisquantumcipher/tap/desktidy-r2-preview
brew install anubisquantumcipher/tap/desktidy-r2-preview
desktidy-r2-preview
```

Formula-only trust is deliberate; whole-tap trust is neither requested nor
required. The formula is bound to:

- tag: `v1.2.0-preview.2`
- source commit: `8b6c09a9b85b5ef382bb76d0e0df7e3c1f7f2a24`
- GitHub source archive SHA-256:
  `15d46b3c829a1af2e212b52f00888198ab51ef0d24838d71edca73918df076a8`
- tap commit: `c8f9e6a9bc8020333c3427ee5c361e0236587e88`

Preview 2 supersedes preview 1 because it restores the exact five-root Desktop
contract and prevents flat native category folders from appearing at the root.

The former `desktidy` CLI formula is disabled because its setup path installs
the retired Desktop authority. It must not be enabled beside native DeskTidy.

`scripts/test-homebrew-source-preview.sh` reconstructs a Git-free source
archive, builds the app with the exact commit identity, verifies the app and
migration bundle identity, runs the sorter self-test on fixture paths, and
proves the loaded-state observations for both DeskTidy services are unchanged.

This preview is replaceable. When Developer ID access exists, the supported
native distribution becomes a Developer ID-signed, hardened-runtime,
notarized artifact delivered through a cask.
