#!/bin/bash
# Local Phase 1B sacrificial observation. NOT run by hosted CI.
# Print-only launchctl. Never bootstrap/bootout/kickstart/enable/disable.
# Never touches the live Desktop or com.sicarii.desktop-autosort*.
set -euo pipefail
# The sole architect-authorized lifecycle is recorded at cbfb795; replay is forbidden.
echo "observe-phase1b: retired after recorded lifecycle; no replay is authorized" >&2
exit 2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
  echo "observe-phase1b: refusing dirty worktree" >&2
  exit 2
fi
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "observe-phase1b: HEAD is not a 40-hex commit" >&2
  exit 2
fi

OUT="$(mktemp -d /tmp/desktidy-phase1b-build-XXXXXX)"
SAC="$(mktemp -d /tmp/desktidy-phase1b-root-XXXXXX)"
AUTHDIR="$(mktemp -d /tmp/desktidy-phase1b-auth-XXXXXX)"
"$ROOT/scripts/build-probe.sh" "$OUT"
PROBE="$OUT/DeskTidySacrificialProbe.app/Contents/MacOS/DeskTidySacrificialProbe"
HASH="$(shasum -a 256 "$PROBE" | awk '{print $1}')"
EXP="$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"
REG="$AUTHDIR/register.json"
UNREG="$AUTHDIR/unregister.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$EXP\",\"nonce\":\"nonce-1b-reg1\"}" > "$REG"
printf '%s' "{\"schema\":1,\"operation\":\"unregister\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$EXP\",\"nonce\":\"nonce-1b-unreg1\"}" > "$UNREG"
chmod 600 "$REG" "$UNREG"

uid="$(id -u)"
echo "PHASE1B_OBSERVE_BEGIN"
echo "commit=$COMMIT"
echo "probe=$PROBE"
echo "executableSHA256=$HASH"
echo "sacrificialRoot=$SAC"
echo "--- pre launchctl print ---"
for label in com.desktidy.sort com.desktidy.notify com.desktidy.sacrificial com.sicarii.desktop-autosort com.sicarii.desktop-autosort-notify; do
  set +e
  launchctl print "gui/${uid}/${label}" >/tmp/dt-1b-pre-"$label".txt 2>&1
  rc=$?
  set -e
  echo "pre $label rc=$rc"
done

set +e
REG_OUT="$("$PROBE" --register --auth-file "$REG" --commit-mutation 2>&1)"
REG_RC=$?
set -e
echo "--- register ---"
echo "$REG_OUT"
echo "register_exit=$REG_RC"

set +e
launchctl print "gui/${uid}/com.desktidy.sacrificial" >/tmp/dt-1b-post-reg-sacrificial.txt 2>&1
POST_REG_RC=$?
set -e
echo "post_register sacrificial print rc=$POST_REG_RC"
sed -n '1,16p' /tmp/dt-1b-post-reg-sacrificial.txt

set +e
UN_OUT="$("$PROBE" --unregister --auth-file "$UNREG" --commit-mutation 2>&1)"
UN_RC=$?
set -e
echo "--- unregister ---"
echo "$UN_OUT"
echo "unregister_exit=$UN_RC"

set +e
launchctl print "gui/${uid}/com.desktidy.sacrificial" >/tmp/dt-1b-post-unreg-sacrificial.txt 2>&1
POST_UN_RC=$?
launchctl print "gui/${uid}/com.sicarii.desktop-autosort" >/tmp/dt-1b-post-personal.txt 2>&1
PERS_RC=$?
set -e
echo "post_unregister sacrificial print rc=$POST_UN_RC"
echo "post_unregister personal print rc=$PERS_RC"
echo "PHASE1B_OBSERVE_END"
echo "register_exit=$REG_RC unregister_exit=$UN_RC"
