#!/bin/bash
# Serialized public-boundary suite for the sacrificial probe.
# Builds under /tmp, feeds real authorization files, never invokes production mutation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d /tmp/dt-1a1-pub-XXXXXX)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if ! printf '%s' "$COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "FAIL: git HEAD is not a 40-hex commit" >&2
  exit 1
fi

PASS=0
FAIL=0
declare -a SEEN=()

expect() {
  local id="$1" want="$2"
  shift 2
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  SEEN+=("$id")
  if [ "$rc" = "$want" ]; then
    echo "PASS  $id  exit=$rc"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $id  want=$want got=$rc"
    echo "$out" | tail -5
    FAIL=$((FAIL + 1))
  fi
}

# Dirty-tree build refusal (no injected identity)
DIRTY="$(mktemp -d /tmp/dt-1a1-dirty-XXXXXX)"
cp -R "$ROOT/." "$DIRTY/"
rm -rf "$DIRTY/.git"
# recreate a git repo that is dirty
git -C "$DIRTY" init -q
git -C "$DIRTY" config user.email t@t
git -C "$DIRTY" config user.name t
git -C "$DIRTY" add -A
git -C "$DIRTY" commit -qm init
echo dirty >> "$DIRTY/README.md"
set +e
"$DIRTY/scripts/build-probe.sh" "$DIRTY/build" >/tmp/dt-dirty-out.txt 2>&1
DRC=$?
set -e
SEEN+=("P13")
if [ "$DRC" -ne 0 ] && grep -q 'dirty worktree' /tmp/dt-dirty-out.txt; then
  echo "PASS  P13  dirty-tree build refused"
  PASS=$((PASS + 1))
else
  echo "FAIL  P13  dirty-tree build not refused (exit=$DRC)"
  FAIL=$((FAIL + 1))
fi

# Short SHA injection refused
set +e
"$ROOT/scripts/build-probe.sh" "$OUT/short" --identity-commit e14c13f >/tmp/dt-short-out.txt 2>&1
SRC=$?
set -e
SEEN+=("P14")
if [ "$SRC" -ne 0 ]; then
  echo "PASS  P14  short SHA identity refused"
  PASS=$((PASS + 1))
else
  echo "FAIL  P14  short SHA accepted"
  FAIL=$((FAIL + 1))
fi

"$ROOT/scripts/build-probe.sh" "$OUT" --identity-commit "$COMMIT"
PROBE="$OUT/DeskTidySacrificialProbe.app/Contents/MacOS/DeskTidySacrificialProbe"
HELPER="$OUT/DeskTidySacrificialProbe.app/Contents/MacOS/SacrificialHelper"
test -x "$PROBE"
HASH="$(shasum -a 256 "$PROBE" | awk '{print $1}')"
# Compiled identity readback
"$PROBE" --plan | grep -q "$COMMIT"
SEEN+=("P15")
echo "PASS  P15  compiled source commit read back"
PASS=$((PASS + 1))
SEEN+=("P16")
echo "PASS  P16  external executable SHA-256 $HASH"
PASS=$((PASS + 1))

write_auth() {
  local dest="$1" root="$2" hash="$3" commit="$4" nonce="$5" extra="${6:-}"
  local exp
  exp="$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$root\",\"bundleSHA256\":\"$hash\",\"sourceCommit\":\"$commit\",\"expiry\":\"$exp\",\"nonce\":\"$nonce\"$extra}" > "$dest"
  chmod 600 "$dest"
}

SAC="$(mktemp -d /tmp/dt-1a1-sac-XXXXXX)"
AUTHDIR="$(mktemp -d /tmp/dt-1a1-auth-XXXXXX)"
ISO_EXP="$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"

GOOD="$AUTHDIR/good.json"
write_auth "$GOOD" "$SAC" "$HASH" "$COMMIT" "nonce-pub1"
expect P01 4 "$PROBE" --register --auth-file "$GOOD"
# grant prepared, no adapter
# reuse same nonce in a fresh process
expect P32 3 "$PROBE" --register --auth-file "$GOOD"

expect P02 2 "$PROBE" --register
expect P03 3 "$PROBE" --register --auth-file "$AUTHDIR/missing.json"

# symlink
ln -s "$GOOD" "$AUTHDIR/link.json"
expect P04 3 "$PROBE" --register --auth-file "$AUTHDIR/link.json"

# 0644
WIDE="$AUTHDIR/wide.json"
write_auth "$WIDE" "$SAC" "$HASH" "$COMMIT" "nonce-wide1"
chmod 644 "$WIDE"
expect P05 3 "$PROBE" --register --auth-file "$WIDE"

# oversized
BIG="$AUTHDIR/big.json"
python3 -c 'open("'"$BIG"'","w").write("a"*5000)'
chmod 600 "$BIG"
expect P06 3 "$PROBE" --register --auth-file "$BIG"

# malformed
MAL="$AUTHDIR/mal.json"
printf 'not-json' > "$MAL"; chmod 600 "$MAL"
expect P07 3 "$PROBE" --register --auth-file "$MAL"

# duplicate nonce key
DUP="$AUTHDIR/dup.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$ISO_EXP\",\"nonce\":\"nonce-dup1\",\"nonce\":\"nonce-dup1\"}" > "$DUP"
chmod 600 "$DUP"
expect P08 3 "$PROBE" --register --auth-file "$DUP"

# extra key
EXT="$AUTHDIR/extra.json"
write_auth "$EXT" "$SAC" "$HASH" "$COMMIT" "nonce-ext1" ",\"extra\":\"x\""
expect P09 3 "$PROBE" --register --auth-file "$EXT"

# trailing garbage
TR="$AUTHDIR/trail.json"
write_auth "$TR" "$SAC" "$HASH" "$COMMIT" "nonce-tr1"
printf ' true' >> "$TR"
expect P10 3 "$PROBE" --register --auth-file "$TR"

# expired
EXP="$AUTHDIR/exp.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"2020-01-01T00:00:00Z\",\"nonce\":\"nonce-exp1\"}" > "$EXP"
chmod 600 "$EXP"
expect P11 3 "$PROBE" --register --auth-file "$EXP"

# wrong operation
UOP="$AUTHDIR/unreg.json"
printf '%s' "{\"schema\":1,\"operation\":\"unregister\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$ISO_EXP\",\"nonce\":\"nonce-uop1\"}" > "$UOP"
chmod 600 "$UOP"
expect P12 3 "$PROBE" --register --auth-file "$UOP"

# zero hash
ZH="$AUTHDIR/zero.json"
write_auth "$ZH" "$SAC" "$(printf '0%.0s' {1..64})" "$COMMIT" "nonce-z1"
expect P17 3 "$PROBE" --register --auth-file "$ZH"

# wrong hash
WH="$AUTHDIR/wrongh.json"
write_auth "$WH" "$SAC" "$(printf 'c%.0s' {1..64})" "$COMMIT" "nonce-wh1"
expect P18 3 "$PROBE" --register --auth-file "$WH"

# stale Phase 0 commit
ST="$AUTHDIR/stale.json"
write_auth "$ST" "$SAC" "$HASH" "0b11c652e364cf47668ba87b4228a0f4ab7974ec" "nonce-st1"
expect P19 3 "$PROBE" --register --auth-file "$ST"

# nonexistent root
MISSROOT="$AUTHDIR/missroot.json"
write_auth "$MISSROOT" "/tmp/dt-1a1-does-not-exist-$$" "$HASH" "$COMMIT" "nonce-mr1"
expect P20 3 "$PROBE" --register --auth-file "$MISSROOT"

# file as root
FROOT="$(mktemp /tmp/dt-1a1-froot-XXXX)"
FR="$AUTHDIR/froot.json"
write_auth "$FR" "$FROOT" "$HASH" "$COMMIT" "nonce-fr1"
expect P21 3 "$PROBE" --register --auth-file "$FR"

# Desktop
DESK="$HOME/Desktop"
DR="$AUTHDIR/desk.json"
write_auth "$DR" "$DESK" "$HASH" "$COMMIT" "nonce-dk1"
expect P22 3 "$PROBE" --register --auth-file "$DR"

# helper hash instead of probe
HH="$AUTHDIR/helper.json"
HHASH="$(shasum -a 256 "$HELPER" | awk '{print $1}')"
write_auth "$HH" "$SAC" "$HHASH" "$COMMIT" "nonce-hh1"
expect P23 3 "$PROBE" --register --auth-file "$HH"

# unreadable
UNR="$AUTHDIR/unreadable.json"
write_auth "$UNR" "$SAC" "$HASH" "$COMMIT" "nonce-unr1"
chmod 000 "$UNR"
expect P25 3 "$PROBE" --register --auth-file "$UNR"
chmod 600 "$UNR" || true

# missing required key
MISSKEY="$AUTHDIR/misskey.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$ISO_EXP\"}" > "$MISSKEY"
chmod 600 "$MISSKEY"
expect P26 3 "$PROBE" --register --auth-file "$MISSKEY"

# duplicate sourceCommit
DUPC="$AUTHDIR/dupc.json"
printf '%s' "{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"$SAC\",\"bundleSHA256\":\"$HASH\",\"sourceCommit\":\"$COMMIT\",\"sourceCommit\":\"$COMMIT\",\"expiry\":\"$ISO_EXP\",\"nonce\":\"nonce-dc1\"}" > "$DUPC"
chmod 600 "$DUPC"
expect P27 3 "$PROBE" --register --auth-file "$DUPC"

# Desktop child (metadata only; no Desktop write)
CHILD="$HOME/Desktop/Projects"
CH="$AUTHDIR/child.json"
write_auth "$CH" "$CHILD" "$HASH" "$COMMIT" "nonce-ch1"
expect P28 3 "$PROBE" --register --auth-file "$CH"

# concurrent reservation: exactly one grant, one refuse
RACE="$AUTHDIR/race.json"
write_auth "$RACE" "$SAC" "$HASH" "$COMMIT" "nonce-racep"
set +e
"$PROBE" --register --auth-file "$RACE" >/tmp/dt-race-a.txt 2>&1 &
PA=$!
"$PROBE" --register --auth-file "$RACE" >/tmp/dt-race-b.txt 2>&1 &
PB=$!
wait "$PA"; RA=$?
wait "$PB"; RB=$?
set -e
SEEN+=("P29")
WINS=0
[ "$RA" = "4" ] && WINS=$((WINS + 1))
[ "$RB" = "4" ] && WINS=$((WINS + 1))
if [ "$WINS" -eq 1 ] && { [ "$RA" = "3" ] || [ "$RB" = "3" ]; }; then
  echo "PASS  P29  concurrent public nonce exactly one winner"
  PASS=$((PASS + 1))
else
  echo "FAIL  P29  concurrent public nonce wins=$WINS ra=$RA rb=$RB"
  FAIL=$((FAIL + 1))
fi

# missing auth already P02/P03
# production ledger: valid grant printed constructions=0
if "$PROBE" --register --auth-file "$GOOD" 2>/dev/null | grep -q 'STOP_BEFORE_PRODUCTION_ADAPTER'; then
  :
fi
# second valid different nonce
GOOD2="$AUTHDIR/good2.json"
write_auth "$GOOD2" "$SAC" "$HASH" "$COMMIT" "nonce-pub2"
OUT2="$("$PROBE" --register --auth-file "$GOOD2" 2>&1 || true)"
SEEN+=("P24")
if echo "$OUT2" | grep -q 'STOP_BEFORE_PRODUCTION_ADAPTER' \
   && echo "$OUT2" | grep -q 'ledger_constructions=0' \
   && echo "$OUT2" | grep -q 'ledger_registers=0'; then
  echo "PASS  P24  valid grant stops before production adapter"
  PASS=$((PASS + 1))
else
  echo "FAIL  P24  missing stop/ledger zero"
  echo "$OUT2" | tail -8
  FAIL=$((FAIL + 1))
fi

# required IDs
REQ="P01 P02 P03 P04 P05 P06 P07 P08 P09 P10 P11 P12 P13 P14 P15 P16 P17 P18 P19 P20 P21 P22 P23 P24 P25 P26 P27 P28 P29 P32"
for id in $REQ; do
  echo "${SEEN[*]}" | grep -qw "$id" || { echo "FAIL: missing expected ID $id"; FAIL=$((FAIL + 1)); }
done

echo "PHASE1A1 PUBLIC: $PASS passed, $FAIL failed, ${#SEEN[@]} cases"
if [ "$PASS" -eq 0 ] || [ "${#SEEN[@]}" -eq 0 ]; then
  echo "FAIL: zero cases"; exit 1
fi
test "$FAIL" -eq 0
