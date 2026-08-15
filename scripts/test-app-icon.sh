#!/bin/bash
set -euo pipefail

APP="${1:?usage: test-app-icon.sh /path/to/DeskTidy.app}"
PLIST="$APP/Contents/Info.plist"
RESOURCES="$APP/Contents/Resources"

[ -f "$PLIST" ] || { echo "app-icon: missing Info.plist" >&2; exit 1; }
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST" 2>/dev/null || true)"
[ "$ICON_NAME" = "DeskTidy.icns" ] || {
  echo "app-icon: expected CFBundleIconFile=DeskTidy.icns, found '${ICON_NAME:-absent}'" >&2
  exit 1
}
ICON="$RESOURCES/$ICON_NAME"
[ -s "$ICON" ] || { echo "app-icon: missing non-empty $ICON_NAME" >&2; exit 1; }

WORK="$(mktemp -d /private/tmp/desktidy-icon-verify.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
/usr/bin/iconutil -c iconset -o "$WORK/DeskTidy.iconset" "$ICON"

for file in \
  icon_16x16.png icon_16x16@2x.png \
  icon_32x32.png icon_32x32@2x.png \
  icon_128x128.png icon_128x128@2x.png \
  icon_256x256.png icon_256x256@2x.png \
  icon_512x512.png icon_512x512@2x.png; do
  [ -s "$WORK/DeskTidy.iconset/$file" ] || {
    echo "app-icon: missing representation $file" >&2
    exit 1
  }
done

case "$(file "$WORK/DeskTidy.iconset/icon_512x512@2x.png")" in
  *"PNG image data, 1024 x 1024"*) ;;
  *) echo "app-icon: 1024px representation is invalid" >&2; exit 1 ;;
esac

/usr/bin/codesign --verify --deep --strict "$APP"
printf 'APP_ICON_GATE=PASS icon=%s representations=10\n' "$ICON"
