#!/bin/bash
set -euo pipefail
APP="${1:?usage: test-migration-bundle.sh DeskTidy.app}"
EXPECTED_COMMIT="${2:-}"
BUNDLE="$APP/Contents/Resources/Migration"
[ -d "$BUNDLE" ] || { echo "migration-bundle: directory absent" >&2; exit 1; }
for file in desktidy-sort desktidy-notify.sh com.desktidy.sort.plist.template com.desktidy.notify.plist.template migrate-live.sh IDENTITY SHA256SUMS; do
  [ -f "$BUNDLE/$file" ] && [ ! -L "$BUNDLE/$file" ] || { echo "migration-bundle: missing or symlinked $file" >&2; exit 1; }
done
[ -x "$BUNDLE/desktidy-sort" ] && [ -x "$BUNDLE/desktidy-notify.sh" ] && [ -x "$BUNDLE/migrate-live.sh" ] || {
  echo "migration-bundle: executable mode absent" >&2; exit 1;
}
if find "$BUNDLE" -type l -print -quit | grep -q .; then echo "migration-bundle: symlink present" >&2; exit 1; fi
(
  cd "$BUNDLE"
  shasum -a 256 -c SHA256SUMS >/dev/null
)
COMMIT="$(sed -n 's/^sourceCommit=//p' "$BUNDLE/IDENTITY")"
printf '%s\n' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "migration-bundle: invalid source identity" >&2
  exit 1
}
[ -z "$EXPECTED_COMMIT" ] || [ "$COMMIT" = "$EXPECTED_COMMIT" ] || { echo "migration-bundle: source mismatch" >&2; exit 1; }
[ "$(lipo -archs "$BUNDLE/desktidy-sort")" = arm64 ] || { echo "migration-bundle: sorter architecture mismatch" >&2; exit 1; }
codesign --verify --strict "$BUNDLE/desktidy-sort"
plutil -lint "$BUNDLE/"*.plist.template >/dev/null
# Notifier must consume DeskTidy's own log and never the personal sorter's log.
grep -F 'DeskTidy' "$BUNDLE/desktidy-notify.sh" >/dev/null
grep -F 'desktidy.log' "$BUNDLE/desktidy-notify.sh" >/dev/null
if grep -F 'DesktopAutoSort/autosort.log' "$BUNDLE/desktidy-notify.sh" >/dev/null; then exit 1; fi
codesign --verify --deep --strict "$APP"
printf 'MIGRATION_BUNDLE_GATE=PASS source=%s files=7\n' "$COMMIT"
