#!/bin/bash
# desktidy — management CLI. Installed on PATH (e.g. by Homebrew) so users can
# set up, check, and remove the background service without cloning the repo.
#
#   desktidy setup [--target DIR]   install + start the background agents
#   desktidy status                 what's running, what's granted, recent moves
#   desktidy sort-now               run one sorting pass right now (foreground)
#   desktidy log                    tail the move log
#   desktidy teardown               stop + remove the agents (files untouched)
set -euo pipefail

# Resolve sibling components regardless of install layout:
#   Homebrew:  <prefix>/bin/desktidy, <prefix>/bin/desktidy-sort,
#              <prefix>/libexec/desktidy-notify.sh, <prefix>/share/desktidy/*.template
#   Repo:      handled by ./install.sh instead of this CLI.
#
# Homebrew installs bin/desktidy as a SYMLINK into the Cellar, so resolve links
# step by step (relative link targets resolve against the link's own directory).
resolve_path() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$p"
}
SELF="$(resolve_path "$0")"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PREFIX="$(dirname "$SELF_DIR")"

# Cellar paths change on every `brew upgrade`; the launchd plists and the Full
# Disk Access grant must use Homebrew's STABLE opt path instead, or the service
# (and the TCC grant) would break at the first upgrade.
if command -v brew >/dev/null 2>&1; then
  BREW_OPT="$(brew --prefix desktidy 2>/dev/null || true)"
  if [ -n "$BREW_OPT" ] && [ -x "$BREW_OPT/bin/desktidy-sort" ]; then
    PREFIX="$BREW_OPT"
    SELF_DIR="$BREW_OPT/bin"
  fi
fi

SORT_BIN="$SELF_DIR/desktidy-sort"
NOTIFY_SH="$PREFIX/libexec/desktidy-notify.sh"
TEMPLATES="$PREFIX/share/desktidy"

APPDIR="$HOME/Library/Application Support/DeskTidy"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*"; exit 1; }

need_components() {
  [ -x "$SORT_BIN" ]   || die "desktidy-sort not found next to this script ($SORT_BIN)"
  [ -f "$NOTIFY_SH" ]  || die "desktidy-notify.sh not found ($NOTIFY_SH)"
  [ -d "$TEMPLATES" ]  || die "plist templates not found ($TEMPLATES)"
}

cmd_setup() {
  local TARGET="$HOME/Desktop"
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        TARGET="$(cd "$2" 2>/dev/null && pwd)" || die "--target folder does not exist: $2"
        shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  need_components
  mkdir -p "$APPDIR" "$LA"

  say "Setting up DeskTidy for: $TARGET"
  "$SORT_BIN" --self-test >/dev/null 2>&1 || die "engine self-test failed"
  ok "Engine self-test passed"

  local gen
  gen() { sed -e "s#__SORT_BIN__#$SORT_BIN#g" -e "s#__NOTIFY_SH__#$NOTIFY_SH#g" \
              -e "s#__APPDIR__#$APPDIR#g" -e "s#__TARGET__#$TARGET#g" "$1"; }
  gen "$TEMPLATES/com.desktidy.sort.plist.template"   > "$LA/com.desktidy.sort.plist"
  gen "$TEMPLATES/com.desktidy.notify.plist.template" > "$LA/com.desktidy.notify.plist"
  plutil -lint "$LA/com.desktidy.sort.plist" >/dev/null
  plutil -lint "$LA/com.desktidy.notify.plist" >/dev/null
  ok "Launch agents installed"

  local lbl
  for lbl in com.desktidy.sort com.desktidy.notify; do
    launchctl bootout "gui/$UID_NUM" "$LA/$lbl.plist" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID_NUM" "$LA/$lbl.plist"
  done
  ok "Agents running (they also auto-start at every login)"

  if command -v terminal-notifier >/dev/null 2>&1; then
    ok "terminal-notifier present — banners will be clickable"
  else
    warn "banners will not be clickable (optional):  brew install terminal-notifier"
  fi

  echo
  if DESKTIDY_TARGET_DIR="$TARGET" "$SORT_BIN" --check-access >/dev/null 2>&1; then
    ok "Full Disk Access already granted"
    echo; say "Done. Drop a file on $(basename "$TARGET") — it files itself in ~20s."
  else
    say "One-time step: grant Full Disk Access"
    echo "  macOS blocks background access to your folders until you allow it once."
    echo "  In the System Settings pane that opens: click +, press ⌘⇧G, paste:"
    echo "      $SELF_DIR"
    echo "  choose  desktidy-sort , turn it ON, then run:  desktidy status"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
  fi
}

cmd_teardown() {
  local lbl
  for lbl in com.desktidy.sort com.desktidy.notify; do
    launchctl bootout "gui/$UID_NUM" "$LA/$lbl.plist" >/dev/null 2>&1 || true
    rm -f "$LA/$lbl.plist"
  done
  ok "Agents stopped and removed. Your folders and sorted files are untouched."
  echo "  (State/logs remain in \"$APPDIR\" — delete that folder too if you wish.)"
}

cmd_status() {
  need_components
  say "DeskTidy status"
  "$SORT_BIN" --health | sed 's/^/  /'
  echo
  local lbl st
  for lbl in com.desktidy.sort com.desktidy.notify; do
    if launchctl print "gui/$UID_NUM/$lbl" >/dev/null 2>&1; then
      st="loaded"
    else
      st="NOT loaded (run: desktidy setup)"
    fi
    printf '  agent %-22s %s\n' "$lbl" "$st"
  done
  echo
  local target
  target="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:DESKTIDY_TARGET_DIR' "$LA/com.desktidy.sort.plist" 2>/dev/null || echo "$HOME/Desktop")"
  if DESKTIDY_TARGET_DIR="$target" "$SORT_BIN" --check-access >/dev/null 2>&1; then
    ok "Full Disk Access: granted (target: $target)"
  else
    warn "Full Disk Access: NOT granted — DeskTidy cannot sort until you allow it."
    echo "    System Settings → Privacy & Security → Full Disk Access → + → $SELF_DIR → desktidy-sort"
  fi
  echo
  if [ -f "$APPDIR/desktidy.log" ]; then
    say "Recent moves"
    tail -5 "$APPDIR/desktidy.log" | sed 's/^/  /'
  fi
}

cmd_sort_now() { need_components; exec "$SORT_BIN" --smart-now --verbose; }
cmd_log()      { exec tail -f "$APPDIR/desktidy.log"; }

case "${1:-help}" in
  setup)    shift; cmd_setup "$@" ;;
  teardown) shift; cmd_teardown ;;
  status)   shift; cmd_status ;;
  sort-now) shift; cmd_sort_now ;;
  log)      shift; cmd_log ;;
  *)
    cat <<'EOF'
desktidy — your Desktop, organized automatically

  desktidy setup [--target DIR]   install + start the background service
  desktidy status                 service, permissions, recent moves
  desktidy sort-now               run one pass right now
  desktidy log                    follow the move log
  desktidy teardown               remove the service (never touches your files)
EOF
    ;;
esac
