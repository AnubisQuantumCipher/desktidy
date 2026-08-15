#!/bin/bash
# Produce a deterministic, local-only RC archive from an existing build-app output.
# This script never builds, launches, installs, registers, or notarizes DeskTidy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$ROOT/build/DeskTidy.app}"
OUTPUT_DIR="${2:-$ROOT/dist-local}"
ARCHIVE_NAME="DeskTidy-local-rc-arm64-macos14.zip"
MANIFEST_NAME="DeskTidy-local-rc-manifest.json"

canonical_path() {
  /usr/bin/python3 - "$1" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
}

refuse_desktop_path() {
  local target desktop
  target="$(canonical_path "$1")"
  desktop="$(canonical_path "$HOME/Desktop")"
  case "$target" in
    "$desktop"|"$desktop"/*)
      echo "package: refusing Desktop path; use a non-Desktop source and output directory" >&2
      exit 2
      ;;
  esac
}

refuse_desktop_path "$SOURCE_APP"
refuse_desktop_path "$OUTPUT_DIR"

if [ ! -d "$SOURCE_APP" ]; then
  echo "package: existing DeskTidy.app required; run scripts/build-app.sh separately" >&2
  exit 2
fi
if [ ! -x "$SOURCE_APP/Contents/MacOS/DeskTidy" ]; then
  echo "package: missing executable: DeskTidy.app/Contents/MacOS/DeskTidy" >&2
  exit 2
fi
if [ ! -f "$SOURCE_APP/Contents/Info.plist" ]; then
  echo "package: missing DeskTidy.app/Contents/Info.plist" >&2
  exit 2
fi

ARCHS="$(lipo -archs "$SOURCE_APP/Contents/MacOS/DeskTidy")"
if [ "$ARCHS" != "arm64" ]; then
  echo "package: expected an arm64-only app binary, found: $ARCHS" >&2
  exit 2
fi
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$SOURCE_APP/Contents/Info.plist")"
if [ "$MINIMUM_MACOS" != "14.0" ]; then
  echo "package: expected LSMinimumSystemVersion 14.0, found: $MINIMUM_MACOS" >&2
  exit 2
fi

COMMIT="$(git -C "$ROOT" rev-parse --verify HEAD^{commit})"
COMMIT_EPOCH="$(git -C "$ROOT" show -s --format=%ct "$COMMIT")"
STAMP="$(TZ=UTC date -r "$COMMIT_EPOCH" +%Y%m%d%H%M.%S)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/desktidy-local-rc.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT
STAGED_APP="$STAGE/DeskTidy.app"
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"

# Local RCs deliberately accept only the ad-hoc signature emitted by build-app.sh.
SIGNING_DETAILS="$(codesign -dvv "$STAGED_APP" 2>&1)"
case "$SIGNING_DETAILS" in
  *"Signature=adhoc"*) ;;
  *)
    echo "package: refusing non-ad-hoc or unsigned app; this is a local RC lane only" >&2
    exit 2
    ;;
esac
codesign --verify --deep --strict "$STAGED_APP"

if spctl --assess --type execute --verbose=4 "$STAGED_APP" >/dev/null 2>&1; then
  GATEKEEPER_ASSESSMENT="accepted"
else
  GATEKEEPER_ASSESSMENT="rejected"
fi

# A source-commit timestamp makes repeat archives of the same app deterministic.
find "$STAGE" -exec touch -h -t "$STAMP" {} +
/usr/bin/python3 - "$STAGE" "$COMMIT" "$COMMIT_EPOCH" "$GATEKEEPER_ASSESSMENT" "$MANIFEST_NAME" <<'PY'
from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
from pathlib import Path

stage = Path(sys.argv[1])
commit = sys.argv[2]
commit_epoch = int(sys.argv[3])
gatekeeper = sys.argv[4]
manifest_name = sys.argv[5]
app = stage / "DeskTidy.app"
records: list[dict[str, object]] = []

for entry in sorted(app.rglob("*"), key=lambda value: value.relative_to(stage).as_posix()):
    relative = entry.relative_to(stage).as_posix()
    if relative.startswith("/") or ".." in Path(relative).parts:
        raise SystemExit(f"unsafe manifest path: {relative}")
    info = entry.lstat()
    if stat.S_ISLNK(info.st_mode):
        raise SystemExit(f"symlinks are not permitted in a local RC: {relative}")
    if stat.S_ISDIR(info.st_mode):
        records.append({"path": relative, "type": "directory", "mode": format(stat.S_IMODE(info.st_mode), "04o"), "size": 0, "sha256": None})
        continue
    if not stat.S_ISREG(info.st_mode):
        raise SystemExit(f"unsupported package entry: {relative}")
    digest = hashlib.sha256()
    with entry.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    records.append({"path": relative, "type": "file", "mode": format(stat.S_IMODE(info.st_mode), "04o"), "size": info.st_size, "sha256": digest.hexdigest()})

manifest = {
    "schemaVersion": 1,
    "artifact": {"archive": "DeskTidy-local-rc-arm64-macos14.zip", "bundle": "DeskTidy.app"},
    "source": {"commit": commit, "commitEpoch": commit_epoch},
    "platform": {"architecture": "arm64", "minimumMacOS": "14.0"},
    "signing": {"identity": "-", "kind": "ad-hoc", "verification": "passed", "notarized": False, "localOnly": True},
    "gatekeeper": {"assessment": gatekeeper, "type": "execute", "localOnly": True},
    "files": records,
}
manifest_path = stage / manifest_name
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
os.utime(manifest_path, (commit_epoch, commit_epoch))
PY

mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/$ARCHIVE_NAME"
MANIFEST="$OUTPUT_DIR/$MANIFEST_NAME"
ARCHIVE_TMP="$OUTPUT_DIR/.${ARCHIVE_NAME}.tmp"
rm -f "$ARCHIVE_TMP"
(
  cd "$STAGE"
  LC_ALL=C TZ=UTC /usr/bin/zip -X -q -r "$ARCHIVE_TMP" "DeskTidy.app" "$MANIFEST_NAME"
)
mv -f "$ARCHIVE_TMP" "$ARCHIVE"
cp "$STAGE/$MANIFEST_NAME" "$MANIFEST"

echo "local RC archive: $ARCHIVE_NAME"
echo "local RC manifest: $MANIFEST_NAME"
echo "source commit: $COMMIT"
echo "signing: ad-hoc local-only; notarization: absent; Gatekeeper assessment: $GATEKEEPER_ASSESSMENT"
