#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO/assets/DeskTidyAppIcon.svg"
OUTPUT="${1:?usage: generate-app-icon.sh /path/to/DeskTidy.icns}"
WORK="$(mktemp -d /private/tmp/desktidy-icon-build.XXXXXX)"
ICONSET="$WORK/DeskTidy.iconset"
MASTER="$WORK/DeskTidy-1024.png"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

[ -f "$SOURCE" ] || { echo "icon: missing source $SOURCE" >&2; exit 2; }
case "$OUTPUT" in
  /private/tmp/*|/private/var/folders/*) ;;
  "$REPO"/build/*) ;;
  *) echo "icon: refusing output outside repository build/ or temporary storage: $OUTPUT" >&2; exit 2 ;;
esac

mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"
/usr/bin/sips -s format png "$SOURCE" --out "$MASTER" >/dev/null
case "$(file "$MASTER")" in
  *"PNG image data, 1024 x 1024"*) ;;
  *) echo "icon: source did not rasterize to 1024 x 1024" >&2; exit 1 ;;
esac

render() {
  local pixels="$1" name="$2"
  /usr/bin/sips -z "$pixels" "$pixels" "$MASTER" --out "$ICONSET/$name" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

/usr/bin/iconutil -c icns -o "$OUTPUT" "$ICONSET"
[ -s "$OUTPUT" ] || { echo "icon: iconutil produced no output" >&2; exit 1; }
printf 'APP_ICON_BUILD=PASS output=%s representations=10\n' "$OUTPUT"
