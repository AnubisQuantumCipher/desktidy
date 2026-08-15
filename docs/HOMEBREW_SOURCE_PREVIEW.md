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

`scripts/test-homebrew-source-preview.sh` reconstructs a Git-free source
archive, builds the app with the exact commit identity, verifies the app and
migration bundle identity, runs the sorter self-test on fixture paths, and
proves the loaded-state observations for both DeskTidy services are unchanged.

This preview is replaceable. When Developer ID access exists, the supported
native distribution becomes a Developer ID-signed, hardened-runtime,
notarized artifact delivered through a cask.
