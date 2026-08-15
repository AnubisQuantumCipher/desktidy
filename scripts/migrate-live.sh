#!/bin/bash
# Transactional DeskTidy authority migration. Default is plan-only.
set -euo pipefail

MODE="${1:---plan}"
shift || true
APP=""
BACKUP=""
TARGET=""
EXISTING_SUPPORT_BACKUP=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --backup) BACKUP="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --existing-support-backup) EXISTING_SUPPORT_BACKUP="${2:-}"; shift 2 ;;
    *) echo "migration: unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$APP" ] && [ -n "$BACKUP" ] && [ -n "$TARGET" ] || {
  echo "usage: migrate-live.sh [--plan|--execute] --app APP --backup DIR --target DIR [--existing-support-backup NEW_DIR]" >&2
  exit 2
}

case "$MODE" in
  --plan)
    cat <<EOF
PLAN ONLY — no files or services are changed.
Candidate app: $APP
Rollback backup: $BACKUP
Target: $TARGET
Existing support backup: ${EXISTING_SUPPORT_BACKUP:-not requested}
Transaction order: verify and stage → old notifier → old sorter → new sorter → new notifier → postconditions.
The old files remain available for rollback; no uninstall-first operation occurs.
EOF
    exit 0
    ;;
  --execute) ;;
  *) echo "migration: first argument must be --plan or --execute" >&2; exit 2 ;;
esac

if [ -n "${DESKTIDY_LAUNCHCTL:-}" ] || [ -n "${DESKTIDY_HOME:-}" ]; then
  [ "${DESKTIDY_TEST_MODE:-0}" = "1" ] || {
    echo "migration: test overrides require DESKTIDY_TEST_MODE=1" >&2
    exit 2
  }
fi

LAUNCHCTL="${DESKTIDY_LAUNCHCTL:-/bin/launchctl}"
USER_HOME="${DESKTIDY_HOME:-$HOME}"
UID_NUM="$(id -u)"
LA="$USER_HOME/Library/LaunchAgents"
OLD_SUPPORT="$USER_HOME/Library/Application Support/DesktopAutoSort"
NEW_SUPPORT="$USER_HOME/Library/Application Support/DeskTidy"
BUNDLE="$APP/Contents/Resources/Migration"
LOCK="$USER_HOME/Library/Application Support/.desktidy-migration.lock"
OLD_SORT_PLIST="$LA/com.sicarii.desktop-autosort.plist"
OLD_NOTIFY_PLIST="$LA/com.sicarii.desktop-autosort-notify.plist"
NEW_SORT_PLIST="$LA/com.desktidy.sort.plist"
NEW_NOTIFY_PLIST="$LA/com.desktidy.notify.plist"

canonical_existing_directory() {
  /usr/bin/python3 - "$1" <<'PY'
from pathlib import Path
import os, stat, sys
p = Path(sys.argv[1]).expanduser()
st = os.lstat(p)
if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
    raise SystemExit(2)
print(p.resolve(strict=True))
PY
}

APP="$(canonical_existing_directory "$APP")" || { echo "migration: app must be an existing non-symlink directory" >&2; exit 2; }
BACKUP="$(canonical_existing_directory "$BACKUP")" || { echo "migration: backup must be an existing non-symlink directory" >&2; exit 2; }
TARGET="$(canonical_existing_directory "$TARGET")" || { echo "migration: target must be an existing non-symlink directory" >&2; exit 2; }
BUNDLE="$APP/Contents/Resources/Migration"
[ -d "$BUNDLE" ] && [ ! -L "$BUNDLE" ] || { echo "migration: verified migration bundle absent" >&2; exit 2; }
[ -f "$BUNDLE/SHA256SUMS" ] && [ -f "$BUNDLE/IDENTITY" ] || { echo "migration: bundle identity absent" >&2; exit 2; }
[ -f "$BACKUP/SHA256SUMS" ] || { echo "migration: backup hash manifest absent" >&2; exit 2; }
if find "$BUNDLE" "$BACKUP" -type l -print -quit | grep -q .; then
  echo "migration: symlinks are forbidden in bundle and backup" >&2
  exit 2
fi
(
  cd "$BUNDLE"
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
)
(
  cd "$BACKUP"
  /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
)
SOURCE_COMMIT="$(sed -n 's/^sourceCommit=//p' "$BUNDLE/IDENTITY")"
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || {
  echo "migration: invalid source identity" >&2
  exit 2
}
if [ "${DESKTIDY_TEST_MODE:-0}" != "1" ]; then
  /usr/bin/codesign --verify --deep --strict "$APP" || { echo "migration: app signature verification failed" >&2; exit 2; }
  /usr/bin/codesign --verify --strict "$BUNDLE/desktidy-sort" || { echo "migration: sorter signature verification failed" >&2; exit 2; }
  /usr/bin/python3 - "$APP/Contents/Resources/DeskTidyBuild.json" "$SOURCE_COMMIT" <<'PY'
import json, sys
try:
    identity = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as error:
    raise SystemExit(f"migration: embedded build identity unreadable: {error}")
if identity.get("sourceCommit") != sys.argv[2]:
    raise SystemExit("migration: app and migration source identities differ")
PY
fi
for file in desktidy-sort desktidy-notify.sh com.desktidy.sort.plist.template com.desktidy.notify.plist.template; do
  [ -f "$BUNDLE/$file" ] && [ ! -L "$BUNDLE/$file" ] || { echo "migration: missing bundle file: $file" >&2; exit 2; }
done
[ -x "$BUNDLE/desktidy-sort" ] && [ -x "$BUNDLE/desktidy-notify.sh" ] || { echo "migration: bundle executables are not executable" >&2; exit 2; }
for file in "$OLD_SORT_PLIST" "$OLD_NOTIFY_PLIST" \
  "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort.plist" \
  "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort-notify.plist"; do
  [ -f "$file" ] && [ ! -L "$file" ] || { echo "migration: required legacy plist absent" >&2; exit 2; }
  /usr/bin/plutil -lint "$file" >/dev/null
 done

# Bind the currently installed legacy plists to the rollback epoch byte-for-byte.
cmp -s "$OLD_SORT_PLIST" "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort.plist" || { echo "migration: live sorter plist differs from backup" >&2; exit 2; }
cmp -s "$OLD_NOTIFY_PLIST" "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort-notify.plist" || { echo "migration: live notifier plist differs from backup" >&2; exit 2; }
[ ! -e "$NEW_SORT_PLIST" ] && [ ! -e "$NEW_NOTIFY_PLIST" ] || {
  echo "migration: prior DeskTidy service installation requires a separately bound upgrade transaction" >&2
  exit 2
}
prior_support=0
if [ -e "$NEW_SUPPORT" ]; then
  [ -d "$NEW_SUPPORT" ] && [ ! -L "$NEW_SUPPORT" ] || {
    echo "migration: existing DeskTidy support is not a regular directory" >&2
    exit 2
  }
  [ -n "$EXISTING_SUPPORT_BACKUP" ] || {
    echo "migration: prior DeskTidy service installation requires a separately bound upgrade transaction" >&2
    exit 2
  }
  case "$EXISTING_SUPPORT_BACKUP" in /*) ;; *) echo "migration: existing support backup must be an absolute path" >&2; exit 2;; esac
  [ ! -e "$EXISTING_SUPPORT_BACKUP" ] || { echo "migration: existing support backup path already exists" >&2; exit 2; }
  canonical_existing_directory "$(dirname "$EXISTING_SUPPORT_BACKUP")" >/dev/null \
    || { echo "migration: existing support backup parent is invalid" >&2; exit 2; }
  if find "$NEW_SUPPORT" -type l -print -quit | grep -q .; then
    echo "migration: symlinks are forbidden in existing DeskTidy support" >&2
    exit 2
  fi
  prior_support=1
elif [ -n "$EXISTING_SUPPORT_BACKUP" ]; then
  echo "migration: existing support backup was requested but no prior support exists" >&2
  exit 2
fi
OLD_TARGET="$(/usr/libexec/PlistBuddy -c 'Print :WatchPaths:0' "$OLD_SORT_PLIST")"
[ "$(canonical_existing_directory "$OLD_TARGET")" = "$TARGET" ] || { echo "migration: legacy target differs from requested target" >&2; exit 2; }

# Re-enumerate every launch-agent WatchPaths declaration at the final pre-lock
# seam. The exact personal sorter is the sole allowed overlapping authority.
AUTHORITY_SCAN="$(/usr/bin/python3 - "$LA" "$TARGET" <<'PY'
from pathlib import Path
import os, plistlib, sys
agents, target = Path(sys.argv[1]), Path(sys.argv[2]).resolve(strict=True)
for path in sorted(agents.glob("*.plist")):
    try:
        with path.open("rb") as handle:
            obj = plistlib.load(handle)
    except Exception as error:
        print(f"AMBIGUOUS:{path.name}:{error}")
        raise SystemExit(2)
    label = obj.get("Label")
    watches = obj.get("WatchPaths", [])
    if not isinstance(label, str) or not isinstance(watches, list):
        if watches:
            print(f"AMBIGUOUS:{path.name}:invalid identity or WatchPaths")
            raise SystemExit(2)
        continue
    for raw in watches:
        if not isinstance(raw, str):
            print(f"AMBIGUOUS:{label}:non-string WatchPaths entry")
            raise SystemExit(2)
        try:
            candidate = Path(raw).expanduser()
            if not candidate.is_absolute():
                raise ValueError("relative WatchPaths entry")
            # Resolve existing symlinked parents while allowing a missing leaf.
            # A nonexistent sibling cannot own the already-existing target,
            # but lexical aliases and symlinked parents must still compare equal.
            watched = candidate.resolve(strict=False)
        except Exception as error:
            print(f"AMBIGUOUS:{label}:{error}")
            raise SystemExit(2)
        if watched == target and label != "com.sicarii.desktop-autosort":
            print(f"FOREIGN:{label}")
            raise SystemExit(3)
print("CLEAR")
PY
)" || {
  case "$AUTHORITY_SCAN" in
    FOREIGN:*) echo "migration: unexpected authority watches target: ${AUTHORITY_SCAN#FOREIGN:}" >&2 ;;
    *) echo "migration: launch-agent authority inventory is ambiguous: $AUTHORITY_SCAN" >&2 ;;
  esac
  exit 2
}
[ "$AUTHORITY_SCAN" = CLEAR ] || { echo "migration: authority inventory did not close" >&2; exit 2; }

if [ "$prior_support" -eq 1 ]; then
  mkdir "$EXISTING_SUPPORT_BACKUP"
  /usr/bin/ditto "$NEW_SUPPORT" "$EXISTING_SUPPORT_BACKUP/DeskTidy"
  (
    cd "$EXISTING_SUPPORT_BACKUP"
    find DeskTidy -type f -print0 | LC_ALL=C sort -z | xargs -0 /usr/bin/shasum -a 256 > SHA256SUMS
    /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
  )
fi

mkdir "$LOCK" 2>/dev/null || { echo "migration: another migration transaction is active" >&2; exit 2; }
STAGE="$(mktemp -d "$USER_HOME/Library/Application Support/.desktidy-stage.XXXXXX")"
rollback_armed=0
cleanup() { rm -rf "$STAGE"; rmdir "$LOCK" 2>/dev/null || true; }
rollback() {
  local original_rc="$1"
  set +e
  "$LAUNCHCTL" bootout "gui/$UID_NUM" "$NEW_NOTIFY_PLIST" >/dev/null 2>&1
  "$LAUNCHCTL" bootout "gui/$UID_NUM" "$NEW_SORT_PLIST" >/dev/null 2>&1
  rm -f "$NEW_NOTIFY_PLIST" "$NEW_SORT_PLIST"
  rm -rf "$NEW_SUPPORT"
  local support_rc=0
  if [ "$prior_support" -eq 1 ]; then
    (
      cd "$EXISTING_SUPPORT_BACKUP"
      /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
    ) && /usr/bin/ditto "$EXISTING_SUPPORT_BACKUP/DeskTidy" "$NEW_SUPPORT"
    support_rc=$?
  fi
  /usr/bin/ditto "$BACKUP/DesktopAutoSort" "$OLD_SUPPORT"
  /usr/bin/ditto "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort.plist" "$OLD_SORT_PLIST"
  /usr/bin/ditto "$BACKUP/LaunchAgents/com.sicarii.desktop-autosort-notify.plist" "$OLD_NOTIFY_PLIST"
  local sort_rc=0 notify_rc=0
  if ! "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort" >/dev/null 2>&1; then
    "$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$OLD_SORT_PLIST"
    sort_rc=$?
  fi
  if ! "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort-notify" >/dev/null 2>&1; then
    "$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$OLD_NOTIFY_PLIST"
    notify_rc=$?
  fi
  "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort" >/dev/null 2>&1
  local sort_print=$?
  "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort-notify" >/dev/null 2>&1
  local notify_print=$?
  cleanup
  if [ "$support_rc" -eq 0 ] && [ "$sort_rc" -eq 0 ] && [ "$notify_rc" -eq 0 ] && [ "$sort_print" -eq 0 ] && [ "$notify_print" -eq 0 ]; then
    echo "MIGRATION=ROLLED_BACK original_exit=$original_rc"
    exit 1
  fi
  echo "MIGRATION=ROLLBACK_FAILED original_exit=$original_rc" >&2
  exit 3
}
on_exit() {
  local rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ] && [ "$rollback_armed" -eq 1 ]; then rollback "$rc"; fi
  cleanup
  exit "$rc"
}
trap on_exit EXIT

if [ "$prior_support" -eq 1 ]; then
  /usr/bin/ditto "$NEW_SUPPORT" "$STAGE/support"
else
  mkdir -p "$STAGE/support"
fi
/usr/bin/ditto "$BUNDLE/desktidy-sort" "$STAGE/support/desktidy-sort"
/usr/bin/ditto "$BUNDLE/desktidy-notify.sh" "$STAGE/support/desktidy-notify.sh"
chmod 755 "$STAGE/support/desktidy-sort" "$STAGE/support/desktidy-notify.sh"
/usr/bin/python3 - "$BUNDLE/com.desktidy.sort.plist.template" "$STAGE/com.desktidy.sort.plist" "$NEW_SUPPORT/desktidy-sort" "$NEW_SUPPORT/desktidy-notify.sh" "$NEW_SUPPORT" "$TARGET" <<'PY'
from pathlib import Path
import sys
src, out, sort_bin, notify, support, target = sys.argv[1:]
text = Path(src).read_text()
for old, new in {'__SORT_BIN__':sort_bin,'__NOTIFY_SH__':notify,'__APPDIR__':support,'__TARGET__':target}.items(): text=text.replace(old,new)
Path(out).write_text(text)
PY
/usr/bin/python3 - "$BUNDLE/com.desktidy.notify.plist.template" "$STAGE/com.desktidy.notify.plist" "$NEW_SUPPORT/desktidy-sort" "$NEW_SUPPORT/desktidy-notify.sh" "$NEW_SUPPORT" "$TARGET" <<'PY'
from pathlib import Path
import sys
src, out, sort_bin, notify, support, target = sys.argv[1:]
text = Path(src).read_text()
for old, new in {'__SORT_BIN__':sort_bin,'__NOTIFY_SH__':notify,'__APPDIR__':support,'__TARGET__':target}.items(): text=text.replace(old,new)
Path(out).write_text(text)
PY
/usr/bin/python3 - "$STAGE/support/config.json" "$TARGET" <<'PY'
import json, os, sys
path, target = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"schema": 1, "target": target}, handle, sort_keys=True, separators=(",", ":"))
    handle.write("\n")
os.chmod(path, 0o644)
PY
/usr/bin/plutil -lint "$STAGE/com.desktidy.sort.plist" "$STAGE/com.desktidy.notify.plist" >/dev/null

# Production quiescence: no known sorter process may be active at the handoff seam.
if [ "${DESKTIDY_TEST_MODE:-0}" != "1" ]; then
  if /usr/bin/pgrep -fal 'desktop-autosort-helper|desktidy-sort' | grep -v '[m]igrate-live.sh' | grep -q .; then
    echo "migration: a sorting process is active; retry only after it is idle" >&2
    exit 2
  fi
fi
"$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort" >/dev/null
"$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort-notify" >/dev/null

rollback_armed=1
"$LAUNCHCTL" bootout "gui/$UID_NUM" "$OLD_NOTIFY_PLIST"
"$LAUNCHCTL" bootout "gui/$UID_NUM" "$OLD_SORT_PLIST"
rm -rf "$NEW_SUPPORT"
mv "$STAGE/support" "$NEW_SUPPORT"
/usr/bin/ditto "$STAGE/com.desktidy.sort.plist" "$NEW_SORT_PLIST"
/usr/bin/ditto "$STAGE/com.desktidy.notify.plist" "$NEW_NOTIFY_PLIST"
"$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$NEW_SORT_PLIST"
"$LAUNCHCTL" bootstrap "gui/$UID_NUM" "$NEW_NOTIFY_PLIST"
"$LAUNCHCTL" print "gui/$UID_NUM/com.desktidy.sort" >/dev/null
"$LAUNCHCTL" print "gui/$UID_NUM/com.desktidy.notify" >/dev/null
if "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort" >/dev/null 2>&1 \
  || "$LAUNCHCTL" print "gui/$UID_NUM/com.sicarii.desktop-autosort-notify" >/dev/null 2>&1; then
  echo "migration: legacy label remained loaded" >&2
  exit 1
fi
rollback_armed=0
cleanup
trap - EXIT
printf 'MIGRATION=PASS source=%s target=%s old_files=retained\n' "$SOURCE_COMMIT" "$TARGET"
