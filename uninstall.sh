#!/bin/bash
# DeskTidy uninstaller. Removes the background agents and the program.
# It does NOT touch your folders or any files DeskTidy sorted — only the tool.
set -euo pipefail

APPDIR="$HOME/Library/Application Support/DeskTidy"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
say "Uninstalling DeskTidy…"

for lbl in com.desktidy.sort com.desktidy.notify; do
  launchctl bootout "gui/$UID_NUM" "$LA/$lbl.plist" >/dev/null 2>&1 || true
  rm -f "$LA/$lbl.plist"
  echo "  removed agent: $lbl"
done

# Remove only the program's own files. Never the user's sorted files/folders.
if [ -d "$APPDIR" ]; then
  rm -f "$APPDIR/desktidy-sort" "$APPDIR/desktidy-notify.sh" \
        "$APPDIR/desktidy.log" "$APPDIR/desktidy.lock" \
        "$APPDIR/smart-triage.last" "$APPDIR/smart-triage-cache.json" \
        "$APPDIR/notify.trace.log" "$APPDIR"/agent.*.log "$APPDIR"/notify.*.log
  rmdir "$APPDIR" 2>/dev/null || true
  echo "  removed program files in: $APPDIR"
fi

echo
say "Done. DeskTidy is uninstalled."
echo "  Your folders and everything DeskTidy ever sorted are untouched."
echo "  You may also remove desktidy-sort from System Settings → Full Disk Access."
