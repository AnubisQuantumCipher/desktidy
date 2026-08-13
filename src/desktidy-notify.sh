#!/bin/bash
# DeskTidy notifier — real-time, clickable macOS banners for each file DeskTidy
# files. Tails the move log and posts a notification per NEW move / error.
# Needs no special access: it only reads a log file and posts notifications.
# It never moves, opens, or deletes any of your files.

APPDIR="$HOME/Library/Application Support/DeskTidy"
LOG="$APPDIR/desktidy.log"
TARGET="${DESKTIDY_TARGET_DIR:-$HOME/Desktop}"

# Clickable banners use terminal-notifier if present; otherwise fall back to a
# plain (non-clickable) banner via osascript. Sorting works either way.
TN="/opt/homebrew/bin/terminal-notifier"
[ -x "$TN" ] || TN="$(command -v terminal-notifier 2>/dev/null)"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
squote() { local s="$1"; printf "'%s'" "${s//\'/\'\\\'\'}"; }

# notify <title> <subtitle> <message> <sound|""> <clickpath|""> <reveal|open> <breakDnD:0|1>
notify() {
  local title="$1" subtitle="$2" message="$3" snd="$4" clickpath="$5" mode="$6" breakdnd="$7"
  printf '%s\tposted: %s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$title" "$message" >> "$APPDIR/notify.trace.log" 2>/dev/null
  if [ -n "$TN" ]; then
    local args=(-title "$title" -subtitle "$subtitle" -message "$message")
    [ -n "$snd" ] && args+=(-sound "$snd")
    [ "$breakdnd" = "1" ] && args+=(-ignoreDnD)
    if [ -n "$clickpath" ]; then
      if [ "$mode" = "open" ]; then args+=(-execute "open $(squote "$clickpath")")
      else args+=(-execute "open -R $(squote "$clickpath")"); fi
    fi
    "$TN" "${args[@]}" >/dev/null 2>&1
  else
    /usr/bin/osascript \
      -e 'on run {t, s, m, snd}' \
      -e 'if snd is "" then' -e '  display notification m with title t subtitle s' \
      -e 'else' -e '  display notification m with title t subtitle s sound name snd' \
      -e 'end if' -e 'end run' -- "$title" "$subtitle" "$message" "$snd" >/dev/null 2>&1
  fi
}

for _ in $(seq 1 60); do [ -f "$LOG" ] && break; sleep 2; done
[ -f "$LOG" ] || exit 0

/usr/bin/tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
  payload="${line#*$'\t'}"
  case "$payload" in
    *" -> "*)
      name="$(trim "${payload%%->*}")"
      dest="$(trim "${payload#*->}")"; dest="${dest%/}"
      notify "📥 Filed to $dest" "click to reveal in Finder" "$name" "" "$TARGET/$dest/$name" "reveal" "0" ;;
    ERROR:*|*"ERROR:"*)
      notify "⚠️ DeskTidy error" "click to open the log" "$payload" "Basso" "$LOG" "open" "1" ;;
    SMART:*wrote*suggestion*)
      notify "💡 Inbox suggestions updated" "click to read" "$payload" "" "$TARGET/Inbox/SMART_TRIAGE_SUGGESTIONS.md" "open" "0" ;;
    *) : ;;
  esac
done
