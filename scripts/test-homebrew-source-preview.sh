#!/bin/bash
# Prove the source-built Homebrew preview can build from a checksum-bound source
# archive without registering, loading, or replacing any movement authority.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="$(git -C "$ROOT" rev-parse --verify HEAD^{commit})"
WORK="$(mktemp -d /private/tmp/desktidy-homebrew-preview.XXXXXX)"
cleanup() {
  rc=$?
  trap - EXIT
  find "$WORK" -depth -delete || true
  exit "$rc"
}
trap cleanup EXIT

git clone -q --no-hardlinks "$ROOT" "$WORK/checkout"
if DESKTIDY_SOURCE_COMMIT="0000000000000000000000000000000000000000" \
  "$WORK/checkout/scripts/build-app.sh" "$WORK/mismatch" >"$WORK/mismatch.log" 2>&1; then
  echo "preview: mismatched checkout identity was accepted" >&2
  exit 1
fi
grep -Fq "does not match checkout HEAD" "$WORK/mismatch.log"

mkdir -p "$WORK/source"
git -C "$ROOT" archive --format=tar "$COMMIT" | tar -xf - -C "$WORK/source"
test ! -e "$WORK/source/.git"

before_sort="$(launchctl print "gui/$(id -u)/com.desktidy.sort" >/dev/null 2>&1; echo $?)"
before_notify="$(launchctl print "gui/$(id -u)/com.desktidy.notify" >/dev/null 2>&1; echo $?)"
DESKTIDY_SOURCE_COMMIT="$COMMIT" \
  "$WORK/source/scripts/build-app.sh" "$WORK/build"
after_sort="$(launchctl print "gui/$(id -u)/com.desktidy.sort" >/dev/null 2>&1; echo $?)"
after_notify="$(launchctl print "gui/$(id -u)/com.desktidy.notify" >/dev/null 2>&1; echo $?)"

test "$before_sort" = "$after_sort"
test "$before_notify" = "$after_notify"
test "$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sourceCommit"])' \
  "$WORK/build/DeskTidy.app/Contents/Resources/DeskTidyBuild.json")" = "$COMMIT"
grep -Fxq "sourceCommit=$COMMIT" \
  "$WORK/build/DeskTidy.app/Contents/Resources/Migration/IDENTITY"
codesign --verify --deep --strict "$WORK/build/DeskTidy.app"

fixture="$WORK/fixture"
mkdir -p "$fixture/target" "$fixture/agents" "$fixture/app"
printf '%s\n' '{}' > "$fixture/state.json"
DESKTIDY_TARGET_DIR="$fixture/target" \
DESKTIDY_AGENTS_DIR="$fixture/agents" \
DESKTIDY_APP_DIR="$fixture/app" \
DESKTIDY_LAUNCHD_STATE_FILE="$fixture/state.json" \
  "$WORK/build/DeskTidy.app/Contents/Resources/Migration/desktidy-sort" --self-test >/dev/null

echo "HOMEBREW_SOURCE_PREVIEW=PASS source=$COMMIT authority_mutations=0"
