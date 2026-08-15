#!/bin/bash
# Build the DeskTidy menu-bar app (R1A read-only trust surface) without Xcode
# project files: plain swiftc + a hand-rolled bundle, ad-hoc signed.
#
#   scripts/build-app.sh [output-dir]     # default: build/
#
# The app links the canonical product API and its shared state dependencies.
# DeskTidy.swift is deliberately excluded: it is the CLI executable entrypoint.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$REPO/build}"
APP="$OUT/DeskTidy.app"
MACOS_MIN="14.0"

refuse_desktop_target() {
  local target desktop
  target="$(/usr/bin/python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
  desktop="$(/usr/bin/python3 - "$HOME/Desktop" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
  case "$target" in
    "$desktop"|"$desktop"/*)
      echo "build: refusing Desktop target; use a non-Desktop build directory" >&2
      exit 2
      ;;
  esac
}

refuse_desktop_target "$OUT"
if ! git -C "$REPO" diff --quiet || ! git -C "$REPO" diff --cached --quiet; then
  echo "build: refusing a dirty source tree; commit the exact local RC source first" >&2
  exit 2
fi
SOURCE_COMMIT="$(git -C "$REPO" rev-parse --verify HEAD^{commit})"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -parse-as-library \
  -target "arm64-apple-macosx$MACOS_MIN" \
  "$REPO/src/Config.swift" \
  "$REPO/src/Paths.swift" \
  "$REPO/src/TargetResolver.swift" \
  "$REPO/src/NativeConfigParser.swift" \
  "$REPO/src/NativeConfiguration.swift" \
  "$REPO/src/NativeConfigurationStore.swift" \
  "$REPO/src/ProductIdentity.swift" \
  "$REPO/src/Authority.swift" \
  "$REPO/src/Receipts.swift" \
  "$REPO/src/EffectiveState.swift" \
  "$REPO/src/HistoryQuery.swift" \
  "$REPO/src/CanonicalApplicationCore.swift" \
  "$REPO/src/IntentAdapter.swift" \
  "$REPO/src/ReceiptNotifications.swift" \
  "$REPO/app/DeskTidyIntents.swift" \
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
cat > "$APP/Contents/Resources/DeskTidyBuild.json" <<BUILDINFO
{"sourceCommit":"$SOURCE_COMMIT","minimumMacOS":"$MACOS_MIN","architecture":"arm64","signing":"ad-hoc-local-only"}
BUILDINFO


codesign -s - -i com.desktidy.app --force "$APP"
echo "built local-only ad-hoc app: $APP"
echo "signing: ad-hoc (-); not Developer ID signed, not notarized, and not for distribution"
