#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATE="$ROOT/scripts/migrate-live.sh"
FIXTURE="$(mktemp -d /private/tmp/desktidy-migration-test.XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT

fail() { echo "LIVE_MIGRATION_TEST=FAIL $*" >&2; exit 1; }

/usr/bin/python3 - "$MIGRATE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"^SORTING_PROCESS_PATTERN='([^']+)'$", text, re.MULTILINE)
assert match, "missing sorting process pattern"
pattern = re.compile(match.group(1))
assert pattern.search("/bin/bash /Users/test/Library/Application Support/DesktopAutoSort/desktop-autosort-helper")
assert pattern.search("/Users/test/Library/Application Support/DeskTidy/desktidy-sort --once")
assert not pattern.search("/usr/bin/pgrep -fal desktop-autosort-helper|desktidy-sort")
assert not pattern.search("/bin/bash migrate-live.sh --app /tmp/DeskTidy.app")
PY

make_world() {
  local world="$1"
  local home="$world/home" backup="$world/backup" bundle="$world/app/Contents/Resources/Migration"
  mkdir -p "$home/Library/LaunchAgents" "$home/Library/Application Support/DesktopAutoSort" \
    "$backup/LaunchAgents" "$backup/DesktopAutoSort" "$bundle" "$world/target" "$world/bin" "$world/state"
  printf '#!/bin/sh\nexit 0\n' > "$home/Library/Application Support/DesktopAutoSort/desktop-autosort-helper"
  printf '#!/bin/sh\nexit 0\n' > "$home/Library/Application Support/DesktopAutoSort/desktop-autosort-notify.sh"
  chmod 755 "$home/Library/Application Support/DesktopAutoSort/"desktop-autosort-*
  cat > "$home/Library/LaunchAgents/com.sicarii.desktop-autosort.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.sicarii.desktop-autosort</string><key>ProgramArguments</key><array><string>$home/Library/Application Support/DesktopAutoSort/desktop-autosort-helper</string></array><key>WatchPaths</key><array><string>$world/target</string></array></dict></plist>
PLIST
  cat > "$home/Library/LaunchAgents/com.sicarii.desktop-autosort-notify.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.sicarii.desktop-autosort-notify</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>$home/Library/Application Support/DesktopAutoSort/desktop-autosort-notify.sh</string></array></dict></plist>
PLIST
  cp "$home/Library/LaunchAgents/"com.sicarii.desktop-autosort*.plist "$backup/LaunchAgents/"
  cp "$home/Library/Application Support/DesktopAutoSort/"* "$backup/DesktopAutoSort/"
  (cd "$backup" && find LaunchAgents DesktopAutoSort -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > SHA256SUMS)

  printf '#!/bin/sh\nexit 0\n' > "$bundle/desktidy-sort"
  printf '#!/bin/sh\nexit 0\n' > "$bundle/desktidy-notify.sh"
  chmod 755 "$bundle/desktidy-sort" "$bundle/desktidy-notify.sh"
  cat > "$bundle/com.desktidy.sort.plist.template" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.desktidy.sort</string><key>ProgramArguments</key><array><string>__SORT_BIN__</string></array><key>EnvironmentVariables</key><dict><key>DESKTIDY_TARGET_DIR</key><string>__TARGET__</string></dict><key>WatchPaths</key><array><string>__TARGET__</string></array></dict></plist>
PLIST
  cat > "$bundle/com.desktidy.notify.plist.template" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.desktidy.notify</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>__NOTIFY_SH__</string></array><key>EnvironmentVariables</key><dict><key>DESKTIDY_TARGET_DIR</key><string>__TARGET__</string></dict></dict></plist>
PLIST
  printf 'sourceCommit=%s\n' '0123456789abcdef0123456789abcdef01234567' > "$bundle/IDENTITY"
  (cd "$bundle" && find . -type f ! -name SHA256SUMS -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > SHA256SUMS)

  touch "$world/state/com.sicarii.desktop-autosort" "$world/state/com.sicarii.desktop-autosort-notify"
  cat > "$world/bin/launchctl" <<'SH'
#!/bin/bash
set -euo pipefail
log="${FAKE_LAUNCHCTL_LOG:?}" state="${FAKE_LAUNCHCTL_STATE:?}"
cmd="$1"; shift
case "$cmd" in
  bootout|bootstrap)
    domain="$1"; plist="$2"; label="$(basename "$plist" .plist)"
    printf '%s %s\n' "$cmd" "$label" >> "$log"
    if [ "${FAKE_FAIL_ACTION:-}" = "$cmd:$label" ]; then exit 5; fi
    if [ "$cmd" = bootstrap ] && [ "${FAKE_FAIL_BOOTSTRAP:-}" = "$label" ]; then exit 5; fi
    if [ "$cmd" = bootstrap ] && [ -f "$state/$label" ]; then exit 5; fi
    if [ "$cmd" = bootout ]; then rm -f "$state/$label"; else touch "$state/$label"; fi
    ;;
  print)
    label="${1##*/}"; [ -f "$state/$label" ]
    ;;
  *) exit 64 ;;
esac
SH
  chmod 755 "$world/bin/launchctl"
}

# Plan-only must not invoke launchctl.
make_world "$FIXTURE/plan"
plan="$($MIGRATE --plan --app "$FIXTURE/plan/app" --backup "$FIXTURE/plan/backup" --target "$FIXTURE/plan/target")"
case "$plan" in *'PLAN ONLY — no files or services are changed.'*'old notifier → old sorter → new sorter → new notifier'*) ;; *) fail "plan disclosure";; esac
[ ! -e "$FIXTURE/plan/launchctl.log" ] || fail "plan invoked launchctl"

# Overrides require explicit test mode.
set +e
HOME="$FIXTURE/plan/home" DESKTIDY_LAUNCHCTL="$FIXTURE/plan/bin/launchctl" "$MIGRATE" --execute \
  --app "$FIXTURE/plan/app" --backup "$FIXTURE/plan/backup" --target "$FIXTURE/plan/target" >"$FIXTURE/unsafe.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] && grep -F 'test overrides require DESKTIDY_TEST_MODE=1' "$FIXTURE/unsafe.out" >/dev/null || fail "override guard"

# An unbound prior DeskTidy service installation must refuse before launchctl.
make_world "$FIXTURE/prior"
mkdir -p "$FIXTURE/prior/home/Library/Application Support/DeskTidy"
set +e
env HOME="$FIXTURE/prior/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/prior/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/prior/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/prior/state" \
  "$MIGRATE" --execute --app "$FIXTURE/prior/app" --backup "$FIXTURE/prior/backup" --target "$FIXTURE/prior/target" \
  >"$FIXTURE/prior/out" 2>&1
prior_rc=$?
set -e
[ "$prior_rc" -eq 2 ] || fail "prior installation was not refused: rc=$prior_rc"
grep -F 'prior DeskTidy service installation requires a separately bound upgrade transaction' "$FIXTURE/prior/out" >/dev/null || fail "prior-install marker"
[ ! -e "$FIXTURE/prior/launchctl.log" ] || fail "prior-install refusal touched launchctl"

# Any unexpected launch agent watching the same canonical root blocks takeover.
make_world "$FIXTURE/foreign"
cat > "$FIXTURE/foreign/home/Library/LaunchAgents/com.example.foreign-sort.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.example.foreign-sort</string><key>ProgramArguments</key><array><string>/bin/true</string></array><key>WatchPaths</key><array><string>$FIXTURE/foreign/target</string></array></dict></plist>
PLIST
set +e
env HOME="$FIXTURE/foreign/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/foreign/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/foreign/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/foreign/state" \
  "$MIGRATE" --execute --app "$FIXTURE/foreign/app" --backup "$FIXTURE/foreign/backup" --target "$FIXTURE/foreign/target" \
  >"$FIXTURE/foreign/out" 2>&1
foreign_rc=$?
set -e
[ "$foreign_rc" -eq 2 ] || fail "foreign authority was not refused: rc=$foreign_rc"
grep -F 'unexpected authority watches target: com.example.foreign-sort' "$FIXTURE/foreign/out" >/dev/null || fail "foreign-authority marker"
[ ! -e "$FIXTURE/foreign/launchctl.log" ] || fail "foreign-authority refusal touched launchctl"

# A missing unrelated watched sibling does not make the existing target ambiguous.
make_world "$FIXTURE/missing-unrelated"
cat > "$FIXTURE/missing-unrelated/home/Library/LaunchAgents/com.example.missing.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>com.example.missing</string><key>ProgramArguments</key><array><string>/bin/true</string></array><key>WatchPaths</key><array><string>$FIXTURE/missing-unrelated/target/../missing-sibling</string></array></dict></plist>
PLIST
set +e
env HOME="$FIXTURE/missing-unrelated/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/missing-unrelated/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/missing-unrelated/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/missing-unrelated/state" \
  "$MIGRATE" --execute --app "$FIXTURE/missing-unrelated/app" --backup "$FIXTURE/missing-unrelated/backup" \
  --target "$FIXTURE/missing-unrelated/target" >"$FIXTURE/missing-unrelated/out" 2>&1
missing_rc=$?
set -e
if [ "$missing_rc" -ne 0 ]; then cat "$FIXTURE/missing-unrelated/out" >&2; fail "missing unrelated watch path rc=$missing_rc"; fi
grep -F 'MIGRATION=PASS' "$FIXTURE/missing-unrelated/out" >/dev/null || fail "missing unrelated success marker"

# Successful atomic handoff.
make_world "$FIXTURE/success"
set +e
env HOME="$FIXTURE/success/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/success/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/success/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/success/state" \
  "$MIGRATE" --execute --app "$FIXTURE/success/app" --backup "$FIXTURE/success/backup" --target "$FIXTURE/success/target" \
  >"$FIXTURE/success/out" 2>&1
success_rc=$?
set -e
if [ "$success_rc" -ne 0 ]; then
  cat "$FIXTURE/success/out" >&2
  fail "success transaction rc=$success_rc"
fi
cat > "$FIXTURE/expected-success" <<'EOF'
bootout com.sicarii.desktop-autosort-notify
bootout com.sicarii.desktop-autosort
bootstrap com.desktidy.sort
bootstrap com.desktidy.notify
EOF
cmp -s "$FIXTURE/expected-success" "$FIXTURE/success/launchctl.log" || fail "success order"
[ -f "$FIXTURE/success/state/com.desktidy.sort" ] && [ -f "$FIXTURE/success/state/com.desktidy.notify" ] || fail "new labels absent"
[ ! -f "$FIXTURE/success/state/com.sicarii.desktop-autosort" ] && [ ! -f "$FIXTURE/success/state/com.sicarii.desktop-autosort-notify" ] || fail "old labels remain loaded"
[ -f "$FIXTURE/success/home/Library/Application Support/DesktopAutoSort/desktop-autosort-helper" ] || fail "old files deleted"
python3 - "$FIXTURE/success/home/Library/Application Support/DeskTidy/config.json" "$FIXTURE/success/target" <<'PY' \
  || fail "successful migration did not persist native target configuration"
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
if config != {"schema": 1, "target": sys.argv[2]}:
    raise SystemExit(f"unexpected config: {config!r}")
PY
grep -F 'MIGRATION=PASS' "$FIXTURE/success/out" >/dev/null || fail "success marker"

# A bound prior DeskTidy support directory is preserved and overlaid, never erased.
make_world "$FIXTURE/upgrade"
mkdir -p "$FIXTURE/upgrade/home/Library/Application Support/DeskTidy"
printf 'preserve-me\n' > "$FIXTURE/upgrade/home/Library/Application Support/DeskTidy/legacy.log"
set +e
env HOME="$FIXTURE/upgrade/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/upgrade/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/upgrade/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/upgrade/state" \
  "$MIGRATE" --execute --app "$FIXTURE/upgrade/app" --backup "$FIXTURE/upgrade/backup" \
  --target "$FIXTURE/upgrade/target" --existing-support-backup "$FIXTURE/upgrade/support-backup" \
  >"$FIXTURE/upgrade/out" 2>&1
upgrade_rc=$?
set -e
if [ "$upgrade_rc" -ne 0 ]; then cat "$FIXTURE/upgrade/out" >&2; fail "bound support upgrade rc=$upgrade_rc"; fi
grep -Fx 'preserve-me' "$FIXTURE/upgrade/home/Library/Application Support/DeskTidy/legacy.log" >/dev/null || fail "prior support not preserved"
grep -Fx 'preserve-me' "$FIXTURE/upgrade/support-backup/DeskTidy/legacy.log" >/dev/null || fail "prior support backup absent"
(cd "$FIXTURE/upgrade/support-backup" && shasum -a 256 -c SHA256SUMS >/dev/null) || fail "prior support backup manifest"
[ -x "$FIXTURE/upgrade/home/Library/Application Support/DeskTidy/desktidy-sort" ] || fail "upgrade sorter absent"
grep -F 'MIGRATION=PASS' "$FIXTURE/upgrade/out" >/dev/null || fail "upgrade success marker"

# A failed bound support upgrade restores the prior support directory byte-for-byte.
make_world "$FIXTURE/upgrade-rollback"
mkdir -p "$FIXTURE/upgrade-rollback/home/Library/Application Support/DeskTidy"
printf 'restore-me\n' > "$FIXTURE/upgrade-rollback/home/Library/Application Support/DeskTidy/legacy.log"
set +e
env HOME="$FIXTURE/upgrade-rollback/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/upgrade-rollback/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/upgrade-rollback/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/upgrade-rollback/state" \
  FAKE_FAIL_BOOTSTRAP=com.desktidy.notify "$MIGRATE" --execute --app "$FIXTURE/upgrade-rollback/app" \
  --backup "$FIXTURE/upgrade-rollback/backup" --target "$FIXTURE/upgrade-rollback/target" \
  --existing-support-backup "$FIXTURE/upgrade-rollback/support-backup" >"$FIXTURE/upgrade-rollback/out" 2>&1
upgrade_rollback_rc=$?
set -e
[ "$upgrade_rollback_rc" -eq 1 ] || fail "bound support rollback rc=$upgrade_rollback_rc"
grep -Fx 'restore-me' "$FIXTURE/upgrade-rollback/home/Library/Application Support/DeskTidy/legacy.log" >/dev/null || fail "bound support rollback did not restore prior bytes"
[ ! -e "$FIXTURE/upgrade-rollback/home/Library/Application Support/DeskTidy/desktidy-sort" ] || fail "bound support rollback retained new sorter"
[ ! -e "$FIXTURE/upgrade-rollback/home/Library/Application Support/DeskTidy/config.json" ] || fail "bound support rollback retained new config"
grep -F 'MIGRATION=ROLLED_BACK' "$FIXTURE/upgrade-rollback/out" >/dev/null || fail "bound support rollback marker"

# Failure after sorter bootstrap must remove it and restore both old labels.
make_world "$FIXTURE/rollback"
set +e
env HOME="$FIXTURE/rollback/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/rollback/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/rollback/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/rollback/state" \
  FAKE_FAIL_BOOTSTRAP=com.desktidy.notify "$MIGRATE" --execute --app "$FIXTURE/rollback/app" \
  --backup "$FIXTURE/rollback/backup" --target "$FIXTURE/rollback/target" >"$FIXTURE/rollback/out" 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "rollback rc=$rc"
cat > "$FIXTURE/expected-rollback" <<'EOF'
bootout com.sicarii.desktop-autosort-notify
bootout com.sicarii.desktop-autosort
bootstrap com.desktidy.sort
bootstrap com.desktidy.notify
bootout com.desktidy.notify
bootout com.desktidy.sort
bootstrap com.sicarii.desktop-autosort
bootstrap com.sicarii.desktop-autosort-notify
EOF
cmp -s "$FIXTURE/expected-rollback" "$FIXTURE/rollback/launchctl.log" || fail "rollback order"
[ -f "$FIXTURE/rollback/state/com.sicarii.desktop-autosort" ] && [ -f "$FIXTURE/rollback/state/com.sicarii.desktop-autosort-notify" ] || fail "old labels not restored"
[ ! -f "$FIXTURE/rollback/state/com.desktidy.sort" ] && [ ! -f "$FIXTURE/rollback/state/com.desktidy.notify" ] || fail "new labels survived rollback"
grep -F 'MIGRATION=ROLLED_BACK' "$FIXTURE/rollback/out" >/dev/null || fail "rollback marker"

# Partial old shutdown: notifier stopped, sorter bootout fails and remains loaded.
# Rollback must detect the loaded sorter rather than bootstrap it twice.
make_world "$FIXTURE/partial"
set +e
env HOME="$FIXTURE/partial/home" DESKTIDY_TEST_MODE=1 DESKTIDY_LAUNCHCTL="$FIXTURE/partial/bin/launchctl" \
  FAKE_LAUNCHCTL_LOG="$FIXTURE/partial/launchctl.log" FAKE_LAUNCHCTL_STATE="$FIXTURE/partial/state" \
  FAKE_FAIL_ACTION=bootout:com.sicarii.desktop-autosort "$MIGRATE" --execute --app "$FIXTURE/partial/app" \
  --backup "$FIXTURE/partial/backup" --target "$FIXTURE/partial/target" >"$FIXTURE/partial/out" 2>&1
partial_rc=$?
set -e
[ "$partial_rc" -eq 1 ] || fail "partial shutdown did not roll back: rc=$partial_rc"
[ -f "$FIXTURE/partial/state/com.sicarii.desktop-autosort" ] && [ -f "$FIXTURE/partial/state/com.sicarii.desktop-autosort-notify" ] || fail "partial shutdown old labels not restored"
grep -F 'MIGRATION=ROLLED_BACK' "$FIXTURE/partial/out" >/dev/null || fail "partial rollback marker"
if grep -Fx 'bootstrap com.sicarii.desktop-autosort' "$FIXTURE/partial/launchctl.log" >/dev/null; then fail "already-loaded sorter was bootstrapped"; fi

printf 'LIVE_MIGRATION_TEST=PASS cases=10\n'
