#!/bin/bash
# Local Phase 1B sacrificial SMAppService observation. NOT run by hosted CI.
# Print-only launchctl. Never bootstrap/bootout/kickstart/enable/disable.
# Never touches the live Desktop or com.sicarii.desktop-autosort*.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UIDN="$(id -u)"
DESKTOP="$(python3 -c 'import os,sys; print(os.path.realpath(os.path.expanduser("~/Desktop")))')"
DEADLINE_SECS=600
LABELS="com.desktidy.sort com.desktidy.notify com.desktidy.sacrificial com.sicarii.desktop-autosort com.sicarii.desktop-autosort-notify"

if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "observe-phase1b: refusing dirty worktree" >&2
  exit 2
fi
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
REMOTE="$(git -C "$ROOT" rev-parse @{u})"
if [ "$COMMIT" != "$REMOTE" ]; then
  echo "observe-phase1b: local HEAD != upstream ($COMMIT vs $REMOTE)" >&2
  exit 2
fi
if ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "observe-phase1b: HEAD is not a 40-hex commit" >&2
  exit 2
fi

if pgrep -f 'observe-phase1b.sh|DeskTidySacrificialProbe --register|--commit-mutation' >/tmp/dt-1b-procs.txt 2>/dev/null; then
  if grep -v "$$" /tmp/dt-1b-procs.txt | grep -q .; then
    echo "observe-phase1b: another lifecycle process is running" >&2
    cat /tmp/dt-1b-procs.txt >&2
    exit 2
  fi
fi

print_label() {
  local tag="$1" label="$2" dest="$3"
  set +e
  launchctl print "gui/${UIDN}/${label}" >"$dest" 2>&1
  local rc=$?
  set -e
  echo "${tag} ${label} rc=${rc}"
  return 0
}

EV="$(mktemp -d /private/tmp/desktidy-phase1b-ev-XXXXXX)"
OUT="$(mktemp -d /private/tmp/desktidy-phase1b-build-XXXXXX)"
SAC="$(mktemp -d /private/tmp/desktidy-phase1b-root-XXXXXX)"
AUTHDIR="$(mktemp -d /private/tmp/desktidy-phase1b-auth-XXXXXX)"
chmod 700 "$SAC" "$AUTHDIR" "$EV" "$OUT"

# Canonical + ownership + mode + Desktop relation
python3 - "$SAC" "$DESKTOP" <<'PY'
import os, sys, stat
sac, desk = sys.argv[1], sys.argv[2]
real = os.path.realpath(sac)
desk_real = os.path.realpath(desk)
st = os.lstat(sac)
if stat.S_ISLNK(st.st_mode):
    raise SystemExit("sacrificial root is a symlink")
if not stat.S_ISDIR(st.st_mode):
    raise SystemExit("sacrificial root is not a directory")
if st.st_uid != os.getuid():
    raise SystemExit("sacrificial root not current-user-owned")
if stat.S_IMODE(st.st_mode) != 0o700:
    raise SystemExit("sacrificial root mode is not 0700")
if real == desk_real:
    raise SystemExit("sacrificial root is Desktop")
if real.startswith(desk_real + os.sep):
    raise SystemExit("sacrificial root is inside Desktop")
if desk_real.startswith(real + os.sep):
    raise SystemExit("sacrificial root is parent of Desktop")
print("canonical_root=" + real)
PY

# Foreign overlap: sacrificial tmp root must not appear in personal/production WatchPaths
python3 - "$SAC" <<'PY'
import os, sys, plistlib
from pathlib import Path
sac = os.path.realpath(sys.argv[1])
agents = Path.home() / "Library" / "LaunchAgents"
protected = {
    "com.sicarii.desktop-autosort",
    "com.sicarii.desktop-autosort-notify",
    "com.desktidy.sort",
    "com.desktidy.notify",
}
for label in protected:
    p = agents / f"{label}.plist"
    if not p.exists():
        continue
    with p.open("rb") as f:
        obj = plistlib.load(f)
    watched = list(obj.get("WatchPaths") or []) + list(obj.get("QueueDirectories") or [])
    for w in watched:
        wreal = os.path.realpath(os.path.expanduser(w))
        if sac == wreal or sac.startswith(wreal + os.sep) or wreal.startswith(sac + os.sep):
            raise SystemExit(f"foreign/protected overlap: {label} watches {wreal}")
print("no_foreign_overlap=1")
PY

echo "PHASE1B_OBSERVE_BEGIN"
echo "commit=$COMMIT"
echo "evidence=$EV"
echo "sacrificialRoot=$SAC"

"$ROOT/scripts/build-probe.sh" "$OUT"
PROBE="$OUT/DeskTidySacrificialProbe.app/Contents/MacOS/DeskTidySacrificialProbe"
HELPER="$OUT/DeskTidySacrificialProbe.app/Contents/MacOS/SacrificialHelper"
PLIST="$OUT/DeskTidySacrificialProbe.app/Contents/Library/LaunchAgents/com.desktidy.sacrificial.plist"
test -x "$PROBE"
test -x "$HELPER"
test -f "$PLIST"
HASH="$(shasum -a 256 "$PROBE" | awk '{print $1}')"
HHASH="$(shasum -a 256 "$HELPER" | awk '{print $1}')"
PHASH="$(shasum -a 256 "$PLIST" | awk '{print $1}')"
PLAN="$("$PROBE" --plan)"
echo "$PLAN" | grep -q "$COMMIT"
echo "probe=$PROBE"
echo "executableSHA256=$HASH"
echo "helperSHA256=$HHASH"
echo "plistSHA256=$PHASH"
codesign -dv --verbose=4 "$OUT/DeskTidySacrificialProbe.app" >"$EV/codesign-probe.txt" 2>&1 || true
codesign -dv --verbose=4 "$HELPER" >"$EV/codesign-helper.txt" 2>&1 || true
echo "$PLAN" >"$EV/plan.txt"

# Pre-state
for label in $LABELS; do
  print_label pre "$label" "$EV/pre-$label.txt"
done
python3 - "$EV" <<'PY'
import pathlib, sys
ev = pathlib.Path(sys.argv[1])
def rc_of(name):
    text = (ev / name).read_text(errors="replace")
    return 0 if "state =" in text or "job state" in text or "gui/" in text and "Could not find service" not in text else 113
# launchctl print writes the service dump on success; error text on failure.
def loaded(path):
    t = path.read_text(errors="replace")
    return "Could not find service" not in t
assert not loaded(ev/"pre-com.desktidy.sort.txt"), "production sort unexpectedly loaded"
assert not loaded(ev/"pre-com.desktidy.notify.txt"), "production notify unexpectedly loaded"
assert not loaded(ev/"pre-com.desktidy.sacrificial.txt"), "sacrificial unexpectedly loaded"
assert loaded(ev/"pre-com.sicarii.desktop-autosort.txt"), "personal mover not loaded"
assert loaded(ev/"pre-com.sicarii.desktop-autosort-notify.txt"), "personal notify not loaded"
print("pre_baseline_ok=1")
PY

EXP="$(date -u -v+10M +%Y-%m-%dT%H:%M:%SZ)"
REG="$AUTHDIR/register.json"
UNREG="$AUTHDIR/unregister.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$EXP\",\"nonce\":\"nonce-r2-reg1\"}" > "$REG"
printf '%s' "{\"schema\":1,\"operation\":\"unregister\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$EXP\",\"nonce\":\"nonce-r2-unreg1\"}" > "$UNREG"
chmod 600 "$REG" "$UNREG"
REG_DIGEST="$(shasum -a 256 "$REG" | awk '{print $1}')"
UNREG_DIGEST="$(shasum -a 256 "$UNREG" | awk '{print $1}')"
echo "register_auth_digest=$REG_DIGEST"
echo "unregister_auth_digest=$UNREG_DIGEST"
echo "$REG_DIGEST" >"$EV/register.auth.sha256"
echo "$UNREG_DIGEST" >"$EV/unregister.auth.sha256"

# Independent watchdog: after deadline, attempt sacrificial unregister only.
WATCHDOG_LOG="$EV/watchdog.log"
(
  sleep "$DEADLINE_SECS"
  echo "watchdog_fired $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$WATCHDOG_LOG"
  if launchctl print "gui/${UIDN}/com.desktidy.sacrificial" >/dev/null 2>&1; then
    echo "watchdog_unregister_attempt" >>"$WATCHDOG_LOG"
    "$PROBE" --unregister --auth-file "$UNREG" --commit-mutation >>"$WATCHDOG_LOG" 2>&1 || true
  else
    echo "watchdog_sacrificial_absent" >>"$WATCHDOG_LOG"
  fi
) >/dev/null 2>&1 &
WATCHDOG_PID=$!
echo "watchdog_pid=$WATCHDOG_PID deadline_secs=$DEADLINE_SECS"

UNREGISTERED=0
do_unregister() {
  if [ "$UNREGISTERED" -eq 1 ]; then
    return 0
  fi
  set +e
  UN_OUT="$("$PROBE" --unregister --auth-file "$UNREG" --commit-mutation 2>&1)"
  UN_RC=$?
  set -e
  echo "$UN_OUT" | tee "$EV/unregister.out"
  echo "unregister_exit=$UN_RC" | tee -a "$EV/unregister.out"
  UNREGISTERED=1
}

cleanup() {
  set +e
  if launchctl print "gui/${UIDN}/com.desktidy.sacrificial" >/dev/null 2>&1; then
    echo "trap: sacrificial still present; unregistering"
    do_unregister
  fi
  kill "$WATCHDOG_PID" >/dev/null 2>&1
  wait "$WATCHDOG_PID" 2>/dev/null
  set -e
}
trap cleanup EXIT

echo "--- register ---"
set +e
REG_OUT="$("$PROBE" --register --auth-file "$REG" --commit-mutation 2>&1)"
REG_RC=$?
set -e
echo "$REG_OUT" | tee "$EV/register.out"
echo "register_exit=$REG_RC" | tee -a "$EV/register.out"
REGISTER_STARTED_AT=$(date +%s)

print_label post_register com.desktidy.sacrificial "$EV/post-reg-com.desktidy.sacrificial.txt"
sed -n '1,40p' "$EV/post-reg-com.desktidy.sacrificial.txt"

# Observed status/label from launchctl dump — do not infer from plist alone.
OBS_LABEL="UNOBSERVED"
if grep -q 'com.desktidy.sacrificial =' "$EV/post-reg-com.desktidy.sacrificial.txt"; then
  OBS_LABEL="com.desktidy.sacrificial"
fi
echo "observed_label=$OBS_LABEL"
echo "$OBS_LABEL" >"$EV/observed-label.txt"

# Heartbeat confinement
if find "$SAC" -type f -name 'heartbeat.json' | grep -q .; then
  echo "heartbeat=present_under_sacrificial_root"
else
  echo "heartbeat=absent"
fi
if find "$DESKTOP" -maxdepth 3 -name 'heartbeat.json' 2>/dev/null | grep -q .; then
  echo "FAIL: heartbeat found under Desktop" >&2
  do_unregister
  exit 3
fi

# Classify
STATUS_LINE="$(printf '%s\n' "$REG_OUT" | sed -n 's/^status=//p' | head -1)"
echo "observed_status_line=$STATUS_LINE"
CLASS="UNKNOWN"
if [ "$REG_RC" -eq 0 ] && [ "$OBS_LABEL" = "com.desktidy.sacrificial" ]; then
  case "$STATUS_LINE" in
    enabled) CLASS="REGISTERED" ;;
    requiresApproval) CLASS="INDETERMINATE" ;;
    unknown*|*) CLASS="INDETERMINATE" ;;
  esac
else
  CLASS="INDETERMINATE"
fi
if [ "$OBS_LABEL" = "UNOBSERVED" ]; then
  CLASS="INDETERMINATE"
fi
echo "register_class=$CLASS"

echo "--- unregister ---"
do_unregister

print_label post_unregister com.desktidy.sacrificial "$EV/post-unreg-com.desktidy.sacrificial.txt"
for label in $LABELS; do
  print_label post "$label" "$EV/post-$label.txt"
done

python3 - "$EV" <<'PY'
import pathlib, sys
ev = pathlib.Path(sys.argv[1])
def loaded(path):
    t = path.read_text(errors="replace")
    return "Could not find service" not in t
if loaded(ev/"post-com.desktidy.sacrificial.txt") or loaded(ev/"post-unreg-com.desktidy.sacrificial.txt"):
    raise SystemExit("sacrificial still loaded after unregister")
if loaded(ev/"post-com.desktidy.sort.txt") or loaded(ev/"post-com.desktidy.notify.txt"):
    raise SystemExit("production DeskTidy label appeared")
if not loaded(ev/"post-com.sicarii.desktop-autosort.txt"):
    raise SystemExit("personal mover missing after run")
if not loaded(ev/"post-com.sicarii.desktop-autosort-notify.txt"):
    raise SystemExit("personal notify missing after run")
print("post_absence_ok=1")
print("personal_mover_unchanged=1")
PY

# Hash durable records then delete auth bytes
if [ -d "$SAC/.desktidy-probe-support" ]; then
  mkdir -p "$EV/support"
  cp -R "$SAC/.desktidy-probe-support/." "$EV/support/" || true
fi
find "$EV" -type f -exec shasum -a 256 {} \; >"$EV/MANIFEST.sha256"
rm -f "$REG" "$UNREG"
echo "auth_bytes_deleted=1"

ELAPSED=$(( $(date +%s) - REGISTER_STARTED_AT ))
echo "rollback_elapsed_secs=$ELAPSED"
echo "PHASE1B_OBSERVE_END"
echo "EVIDENCE=$EV"
echo "register_exit=$REG_RC unregister_class=$CLASS"
