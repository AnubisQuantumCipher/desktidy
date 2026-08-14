#!/bin/bash
# Build the NON-PRODUCTION sacrificial SMAppService probe bundle.
# Compiles and ad-hoc signs only. Does not invoke ServiceManagement mutation
# or launchctl load/unload verbs.
# Ad-hoc signing is development evidence, not Developer ID / notarization.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/build"
INJECTED_COMMIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --identity-commit)
      INJECTED_COMMIT="${2:-}"
      shift 2 ;;
    *)
      OUT="$1"
      shift ;;
  esac
done

if [ -n "$INJECTED_COMMIT" ]; then
  COMMIT="$INJECTED_COMMIT"
else
  if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    echo "build-probe: refusing dirty worktree (no injected test identity)" >&2
    exit 2
  fi
  COMMIT="$(git -C "$REPO" rev-parse HEAD)"
fi
if ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "build-probe: source commit must be a 40-hex SHA (got '$COMMIT')" >&2
  exit 2
fi

APP="$OUT/DeskTidySacrificialProbe.app"
MACOS_MIN="14.0"
GEN="$OUT/GeneratedProbeIdentity.swift"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents" "$APP/Contents/Resources" "$OUT"
cat > "$GEN" <<EOF
enum CompiledProbeIdentity {
    static let sourceCommit = "$COMMIT"
}
EOF

xcrun swiftc -O -parse-as-library \
  -target "arm64-apple-macosx$MACOS_MIN" \
  "$REPO/probe/HelperMain.swift" \
  -o "$APP/Contents/MacOS/SacrificialHelper"

xcrun swiftc -O -parse-as-library \
  -target "arm64-apple-macosx$MACOS_MIN" \
  "$REPO/src/Config.swift" \
  "$REPO/src/Paths.swift" \
  "$REPO/src/ProductIdentity.swift" \
  "$REPO/src/Authority.swift" \
  "$REPO/src/StrictJSONObject.swift" \
  "$REPO/src/SMAdapter.swift" \
  "$REPO/src/MutationInterlock.swift" \
  "$REPO/src/SecureAuthFile.swift" \
  "$REPO/src/DurableNonceStore.swift" \
  "$REPO/src/ProbeIdentity.swift" \
  "$REPO/src/MutationBoundary.swift" \
  "$REPO/src/ProductionEvidence.swift" \
  "$REPO/probe/SMAdapterProduction.swift" \
  "$GEN" \
  "$REPO/probe/ProbeMain.swift" \
  -o "$APP/Contents/MacOS/DeskTidySacrificialProbe"

cp "$REPO/probe/com.desktidy.sacrificial.plist" \
  "$APP/Contents/Library/LaunchAgents/com.desktidy.sacrificial.plist"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.desktidy.sacrificial-probe</string>
    <key>CFBundleName</key><string>DeskTidySacrificialProbe</string>
    <key>CFBundleExecutable</key><string>DeskTidySacrificialProbe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.0.0-phase1a</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>NON-PRODUCTION sacrificial harness — not for distribution</string>
</dict>
</plist>
PLIST

codesign -s - -i com.desktidy.sacrificial-probe --force "$APP"
echo "built (ad-hoc, development evidence only): $APP"
