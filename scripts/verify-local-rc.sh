#!/bin/bash
# Verify a local RC without launching the menu-bar UI or touching the live Desktop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_DIR="$ROOT/dist-local"
ARCHIVE="${1:-$DEFAULT_DIR/DeskTidy-local-rc-arm64-macos14.zip}"
MANIFEST="${2:-$DEFAULT_DIR/DeskTidy-local-rc-manifest.json}"
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
      echo "verify: refusing Desktop path" >&2
      exit 2
      ;;
  esac
}

refuse_desktop_path "$ARCHIVE"
refuse_desktop_path "$MANIFEST"
[ -f "$ARCHIVE" ] || { echo "verify: archive not found" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "verify: manifest not found" >&2; exit 2; }

EXTRACT="$(mktemp -d /private/tmp/desktidy-local-rc-extract.XXXXXX)"
FIXTURE="$(mktemp -d /private/tmp/desktidy-local-rc-fixture.XXXXXX)"
cleanup() { rm -rf "$EXTRACT" "$FIXTURE"; }
trap cleanup EXIT

# Reject a malicious archive before extraction; all package entries must be relative.
/usr/bin/python3 - "$ARCHIVE" "$MANIFEST_NAME" <<'PY'
from pathlib import PurePosixPath
import stat
import sys
import zipfile

archive = sys.argv[1]
manifest_name = sys.argv[2]
with zipfile.ZipFile(archive) as bundle:
    entries = bundle.infolist()
    names = [entry.filename for entry in entries]
if manifest_name not in names:
    raise SystemExit("verify: archive does not contain its manifest")
for entry in entries:
    path = PurePosixPath(entry.filename)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise SystemExit(f"verify: unsafe archive entry: {entry.filename}")
    if stat.S_ISLNK(entry.external_attr >> 16):
        raise SystemExit(f"verify: unsafe archive symlink: {entry.filename}")
PY
/usr/bin/unzip -q "$ARCHIVE" -d "$EXTRACT"
cmp -s "$MANIFEST" "$EXTRACT/$MANIFEST_NAME" || {
  echo "verify: sidecar manifest does not match archive manifest" >&2
  exit 1
}

/usr/bin/python3 - "$EXTRACT/$MANIFEST_NAME" "$EXTRACT" <<'PY'
from __future__ import annotations

import hashlib
import json
import stat
import sys
from pathlib import Path, PurePosixPath

manifest_path = Path(sys.argv[1])
extract = Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 1:
    raise SystemExit("verify: unsupported manifest schema")
if manifest.get("artifact") != {"archive": "DeskTidy-local-rc-arm64-macos14.zip", "bundle": "DeskTidy.app"}:
    raise SystemExit("verify: unexpected artifact identity")
if manifest.get("platform") != {"architecture": "arm64", "minimumMacOS": "14.0"}:
    raise SystemExit("verify: unexpected platform declaration")
signing = manifest.get("signing")
if signing != {"identity": "-", "kind": "ad-hoc", "verification": "passed", "notarized": False, "localOnly": True}:
    raise SystemExit("verify: manifest is not explicitly local-only ad-hoc signing")
gatekeeper = manifest.get("gatekeeper")
if not isinstance(gatekeeper, dict) or gatekeeper.get("assessment") not in {"accepted", "rejected"} or gatekeeper.get("type") != "execute" or gatekeeper.get("localOnly") is not True:
    raise SystemExit("verify: invalid Gatekeeper inspection record")
source = manifest.get("source")
if not isinstance(source, dict) or len(str(source.get("commit", ""))) != 40 or not str(source["commit"]).isalnum() or not isinstance(source.get("commitEpoch"), int):
    raise SystemExit("verify: invalid source commit record")
build_info = extract / "DeskTidy.app/Contents/Resources/DeskTidyBuild.json"
if not build_info.is_file():
    raise SystemExit("verify: embedded build identity is missing")
try:
    embedded = json.loads(build_info.read_text(encoding="utf-8"))
except json.JSONDecodeError as error:
    raise SystemExit(f"verify: malformed embedded build identity: {error}")
if embedded != {
    "sourceCommit": source["commit"],
    "minimumMacOS": "14.0",
    "architecture": "arm64",
    "signing": "ad-hoc-local-only",
}:
    raise SystemExit("verify: embedded build identity differs from manifest")


app = extract / "DeskTidy.app"
if not app.is_dir():
    raise SystemExit("verify: DeskTidy.app missing from archive")
expected = manifest.get("files")
if not isinstance(expected, list) or not expected:
    raise SystemExit("verify: manifest contains no file records")
expected_paths: list[str] = []
for record in expected:
    if not isinstance(record, dict):
        raise SystemExit("verify: malformed file record")
    relative = record.get("path")
    if not isinstance(relative, str):
        raise SystemExit("verify: non-string manifest path")
    parsed = PurePosixPath(relative)
    if parsed.is_absolute() or ".." in parsed.parts or not relative.startswith("DeskTidy.app/"):
        raise SystemExit(f"verify: non-relative manifest path: {relative}")
    expected_paths.append(relative)
if expected_paths != sorted(expected_paths) or len(expected_paths) != len(set(expected_paths)):
    raise SystemExit("verify: manifest file records are not a unique sorted list")

actual_paths = sorted(entry.relative_to(extract).as_posix() for entry in app.rglob("*"))
if actual_paths != expected_paths:
    raise SystemExit("verify: archive contents differ from manifest")
for record in expected:
    relative = record["path"]
    entry = extract / relative
    info = entry.lstat()
    if stat.S_ISLNK(info.st_mode):
        raise SystemExit(f"verify: symlink not permitted: {relative}")
    if record.get("mode") != format(stat.S_IMODE(info.st_mode), "04o"):
        raise SystemExit(f"verify: mode mismatch: {relative}")
    if record.get("type") == "directory":
        if not stat.S_ISDIR(info.st_mode) or record.get("size") != 0 or record.get("sha256") is not None:
            raise SystemExit(f"verify: invalid directory record: {relative}")
        continue
    if record.get("type") != "file" or not stat.S_ISREG(info.st_mode):
        raise SystemExit(f"verify: invalid file record: {relative}")
    if record.get("size") != info.st_size:
        raise SystemExit(f"verify: size mismatch: {relative}")
    digest = hashlib.sha256(entry.read_bytes()).hexdigest()
    if record.get("sha256") != digest:
        raise SystemExit(f"verify: hash mismatch: {relative}")
PY

APP="$EXTRACT/DeskTidy.app"
APP_BIN="$APP/Contents/MacOS/DeskTidy"
ARCHS="$(lipo -archs "$APP_BIN")"
[ "$ARCHS" = "arm64" ] || { echo "verify: expected arm64-only executable, found: $ARCHS" >&2; exit 1; }
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
[ "$MINIMUM_MACOS" = "14.0" ] || { echo "verify: expected macOS 14.0 minimum, found: $MINIMUM_MACOS" >&2; exit 1; }
SIGNING_DETAILS="$(codesign -dvv "$APP" 2>&1)"
case "$SIGNING_DETAILS" in
  *"Signature=adhoc"*) ;;
  *) echo "verify: app is not ad-hoc signed" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"
if spctl --assess --type execute --verbose=4 "$APP" >/dev/null 2>&1; then
  OBSERVED_GATEKEEPER="accepted"
else
  OBSERVED_GATEKEEPER="rejected"
fi

mkdir -p "$FIXTURE/home" "$FIXTURE/agents" "$FIXTURE/target" "$FIXTURE/app-support"
printf '{}\n' > "$FIXTURE/launchd-state.json"
SMOKE_OUTPUT="$(env -i \
  PATH="$PATH" \
  HOME="$FIXTURE/home" \
  DESKTIDY_AGENTS_DIR="$FIXTURE/agents" \
  DESKTIDY_TARGET_DIR="$FIXTURE/target" \
  DESKTIDY_APP_DIR="$FIXTURE/app-support" \
  DESKTIDY_LAUNCHD_STATE_FILE="$FIXTURE/launchd-state.json" \
  "$APP_BIN" --smoke)"
printf '%s\n' "$SMOKE_OUTPUT"
LAST_LINE="$(printf '%s\n' "$SMOKE_OUTPUT" | tail -1)"
[ "$LAST_LINE" = "SMOKE overall=pausedNotLoaded" ] || {
  echo "verify: fixture smoke did not report pausedNotLoaded" >&2
  exit 1
}

echo "verify: manifest, ad-hoc signature, and fresh /private/tmp fixture smoke passed"
echo "verify: Gatekeeper inspection observed: $OBSERVED_GATEKEEPER (policy-dependent; packaged record retained)"
