# DeskTidy R2 — application icon completion receipt

Date: 2026-08-15
Parent checkpoint: `2dbac63acc82a8667e9770c0632a0cfff2841723`

## Defect

The prior app bundle declared no `CFBundleIconFile` and contained no `.icns`
resource. Finder therefore rendered a generic/blank application icon.

RED controls:

```text
app-icon: expected CFBundleIconFile=DeskTidy.icns, found 'absent'
APP_ICON_RED=PASS exit=1
```

The independent verifier also rejected the historical blank-icon RC:

```text
app-icon: expected CFBundleIconFile=DeskTidy.icns, found 'absent'
PACKAGE_ICON_RED=PASS exit=1
```

## Design and Apple bundle contract

The original vector master is `assets/DeskTidyAppIcon.svg`, 1024×1024 with
transparent corners. It retains the existing DeskTidy website identity:
electric sky/deep blue, porcelain file/folder surfaces, and a mint completion
check. The folder plus filed document communicates organization; the check
communicates completed movement rather than deletion.

The deterministic local generator uses the installed Apple-compatible toolchain:

1. `sips` rasterizes the 1024×1024 vector master;
2. `sips` emits 16, 32, 128, 256, and 512 point representations at 1× and 2×;
3. `iconutil` compiles the ten-file `.iconset` into `DeskTidy.icns`;
4. `build-app.sh` embeds the resource and declares
   `CFBundleIconFile=DeskTidy.icns` before ad-hoc signing;
5. `test-app-icon.sh` extracts the `.icns`, requires all ten representations,
   requires the 1024×1024 top representation, and verifies the signed bundle.

No package, model, network call, or generated third-party artwork is required.
Icon Composer was not present in the installed Xcode 26.6 toolchain; `actool`,
`assetutil`, and `iconutil` were present. The `.icns` path preserves the
repository's hand-built macOS 14+ bundle contract.

## GREEN controls

A clean isolated Git checkout ran:

```text
build-app.sh
package-local-rc.sh
verify-local-rc.sh
```

Observed:

```text
APP_ICON_BUILD=PASS representations=10
APP_ICON_GATE=PASS representations=10
PACKAGE_ICON_MANIFEST=PASS
verify: manifest, app icon, ad-hoc signature, and fresh /private/tmp fixture smoke passed
```

Generated `.icns` SHA-256 in the clean probe:

```text
599fa9ce39dc64c4322c96f8515085250006b12e68b0837e06b1d0a0879b762e
```

Source SVG SHA-256:

```text
b46d12021d0f2f869c982c41f41e2d87b602ebd8df83b2e7d8e42a437e73128c
```

## Visible Finder evidence

Finder visibly rendered the packaged DeskTidy mark in dark appearance at its
standard icon size. The blue rounded-square silhouette, folder/document, and
mint completion check remained recognizable; the generic/blank icon was absent.

Evidence:

```text
docs/evidence/assets/R2_APP_ICON_FINDER.png
```

SHA-256:

```text
c1b08e0830efd130e4eb5c71b9c2912b25d96a6165f774bb5839dde2817fbc87
```

## Non-claims

- This icon work does not Developer ID sign or notarize the app.
- It does not install or register DeskTidy as the live Desktop authority.
- It does not unload, modify, or replace the personal sorter/notifier.
- The clean probe commit is disposable verification identity, not a published
  product checkpoint.

## Hosted portability scar

Published checkpoint `29dbcbf6b880db63f3af2422fa196c4f52db2ba8`
failed hosted run `31869051879` on both macOS lanes before app compilation
completed. CI invoked `build-app.sh build`; the generator checked the safe
relative `build/.../DeskTidy.icns` string before resolving it beneath the
repository and rejected it. Absolute `/private/tmp` canonical runs did not
exercise that spelling.

The correction canonicalizes the requested output before applying the same
allowlist. A clean CI-equivalent probe proved relative `build/...` succeeds;
an output beneath `$HOME` still exits 2 and creates no file. The failed run is
retained here rather than overwritten by the corrected hosted result.
