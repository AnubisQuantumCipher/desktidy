#!/bin/bash
# Hermetic packaging controls; no app build, service, Desktop, or launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-local-rc.sh"
WORK="$(mktemp -d /private/tmp/desktidy-local-rc-test.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# The verifier must reject a ZIP symlink before extraction. The link target is
# inert because this archive intentionally contains no nested payload entry.
ARCHIVE="$WORK/symlink.zip"
SIDECAR="$WORK/manifest.json"
: > "$SIDECAR"
/usr/bin/python3 - "$ARCHIVE" <<'PY'
import stat
import sys
import zipfile

archive = sys.argv[1]
with zipfile.ZipFile(archive, "w") as bundle:
    manifest = zipfile.ZipInfo("DeskTidy-local-rc-manifest.json")
    bundle.writestr(manifest, "{}")
    link = zipfile.ZipInfo("DeskTidy.app/Contents/MacOS")
    link.create_system = 3
    link.external_attr = (stat.S_IFLNK | 0o777) << 16
    bundle.writestr(link, "/private/tmp/desktidy-local-rc-test-target")
PY

set +e
OUTPUT="$($VERIFY "$ARCHIVE" "$SIDECAR" 2>&1)"
STATUS=$?
set -e
if [ "$STATUS" -eq 0 ]; then
  echo "FAIL: verifier accepted a ZIP symlink" >&2
  exit 1
fi
case "$OUTPUT" in
  *"unsafe archive symlink"*) ;;
  *)
    echo "FAIL: verifier did not reject the ZIP symlink before extraction: $OUTPUT" >&2
    exit 1
    ;;
esac

echo "local-rc-packaging: PASS"
