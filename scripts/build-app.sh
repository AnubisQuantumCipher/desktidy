#!/bin/bash
# Build the DeskTidy menu-bar app (R1A read-only trust surface) without Xcode
# project files: plain swiftc + a hand-rolled bundle, ad-hoc signed.
#
#   scripts/build-app.sh [output-dir]     # default: build/
#
# The app compiles the SHARED state sources (Config, Authority, Receipts,
# EffectiveState) plus app/DeskTidyApp.swift — the same truth the CLI prints
# via `desktidy-sort --effective-state`.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$REPO/build}"
APP="$OUT/DeskTidy.app"
MACOS_MIN="14.0"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -parse-as-library \
  -target "arm64-apple-macosx$MACOS_MIN" \
  "$REPO/src/Config.swift" \
  "$REPO/src/Paths.swift" \
  "$REPO/src/TargetResolver.swift" \
  "$REPO/src/ProductIdentity.swift" \
  "$REPO/src/Authority.swift" \
  "$REPO/src/Receipts.swift" \
  "$REPO/src/EffectiveState.swift" \
  "$REPO/app/DeskTidyApp.swift" \
  -o "$APP/Contents/MacOS/DeskTidy"

# Universal note: CI builds the native slice only; release builds add x86_64
# via lipo when distribution (R4) begins.

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.desktidy.app</string>
    <key>CFBundleName</key><string>DeskTidy</string>
    <key>CFBundleExecutable</key><string>DeskTidy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>$MACOS_MIN</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT — github.com/AnubisQuantumCipher/desktidy</string>
</dict>
</plist>
PLIST

codesign -s - -i com.desktidy.app --force "$APP"
echo "built: $APP"
