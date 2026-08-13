#!/bin/bash
# DeskTidy installer. Compiles locally, installs two launchd agents, and guides
# the one-time Full Disk Access grant. Safe to re-run (it just rebuilds/reloads).
#
#   ./install.sh                 # organize your Desktop (default)
#   ./install.sh --target ~/Downloads   # organize a different folder instead
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$HOME/Library/Application Support/DeskTidy"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"
TARGET="$HOME/Desktop"

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="$(cd "$2" 2>/dev/null && pwd)" || { echo "Error: --target folder does not exist: $2"; exit 2; }
      shift 2 ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done
[ -d "$TARGET" ] || { echo "Error: target folder does not exist: $TARGET"; exit 2; }

say() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

say "DeskTidy installer"
echo "  Target folder: $TARGET"
echo

# 1) toolchain
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Install Apple's command-line tools first:"
  echo "    xcode-select --install"
  echo "then re-run ./install.sh"
  exit 1
fi
ok "Swift toolchain present"

mkdir -p "$APPDIR" "$LA"

# 2) build (FoundationModels/AI path auto-included only on macOS 26+ SDKs)
say "Building…"
xcrun swiftc -O -parse-as-library "$SCRIPT_DIR"/src/*.swift -o "$APPDIR/desktidy-sort"
codesign -s - -i com.desktidy.sort "$APPDIR/desktidy-sort" >/dev/null 2>&1 || true
ok "Built and signed: $APPDIR/desktidy-sort"

# 3) self-test — refuse to install a broken build
if "$APPDIR/desktidy-sort" --self-test >/dev/null 2>&1; then ok "Self-test passed"
else echo "Self-test FAILED — aborting install."; exit 1; fi

# 4) notifier + clickable-banner dependency (optional)
cp "$SCRIPT_DIR/src/desktidy-notify.sh" "$APPDIR/desktidy-notify.sh"; chmod +x "$APPDIR/desktidy-notify.sh"
if command -v terminal-notifier >/dev/null 2>&1; then
  ok "terminal-notifier found — banners will be clickable"
else
  warn "terminal-notifier not installed — banners will still appear but won't be clickable."
  warn "For clickable banners:  brew install terminal-notifier   (then re-run this installer)"
fi

# 5) generate + install launchd agents from templates
gen() { sed -e "s#__APPDIR__#$APPDIR#g" -e "s#__TARGET__#$TARGET#g" "$1"; }
gen "$SCRIPT_DIR/launchagents/com.desktidy.sort.plist.template"   > "$LA/com.desktidy.sort.plist"
gen "$SCRIPT_DIR/launchagents/com.desktidy.notify.plist.template" > "$LA/com.desktidy.notify.plist"
plutil -lint "$LA/com.desktidy.sort.plist" >/dev/null && plutil -lint "$LA/com.desktidy.notify.plist" >/dev/null
ok "Installed launch agents"

for lbl in com.desktidy.sort com.desktidy.notify; do
  launchctl bootout "gui/$UID_NUM" "$LA/$lbl.plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$UID_NUM" "$LA/$lbl.plist"
done
ok "Agents loaded (will also auto-start at every login)"

# 6) health + read-only Full Disk Access check (this probe NEVER moves anything)
echo; "$APPDIR/desktidy-sort" --health | sed 's/^/  /'
echo
if DESKTIDY_TARGET_DIR="$TARGET" "$APPDIR/desktidy-sort" --check-access >/dev/null 2>&1; then
  ok "Full Disk Access already granted — DeskTidy can read $TARGET"
else
  say "One-time step: grant Full Disk Access"
  echo "  A background helper can't touch your folder until you allow it once."
  echo "  Opening System Settings → Privacy & Security → Full Disk Access…"
  echo
  echo "  1. Click the + button."
  echo "  2. Press ⌘⇧G and paste this path, then press Enter:"
  echo "        $APPDIR"
  echo "  3. Select  desktidy-sort  and turn its switch ON, then re-run ./install.sh."
  echo
  [ "${DESKTIDY_SKIP_FDA_UI:-0}" = "1" ] || open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
fi

echo
say "Done. DeskTidy is installed."
echo "  • Drop any file on your $(basename "$TARGET") — it files itself in ~20s with a banner."
echo "  • Log of every move:  $APPDIR/desktidy.log"
echo "  • Customize folders/rules: edit src/Config.swift then re-run ./install.sh"
echo "  • Uninstall anytime:  ./uninstall.sh   (your files are never touched)"
