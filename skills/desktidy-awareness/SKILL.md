---
name: desktidy-awareness
description: Use when working with files on this Mac's Desktop (or any DeskTidy-watched folder) — writing, saving, or looking for files there — or when a file that was just created seems to have vanished. DeskTidy is a background service that automatically moves loose files into category folders about 20 seconds after they settle; this skill explains where files go, how to find anything instantly via the move log, and how to pause the service for Desktop-heavy work.
---

# Working alongside DeskTidy

DeskTidy is a background launchd service on this Mac that **automatically files
loose items** dropped at the root of a watched folder (default: `~/Desktop`)
into category subfolders. If you write a file there and it "disappears," it was
not deleted — it was filed, and the exact destination was logged.

## The one-line answer to "where did my file go?"

```bash
grep -F "<filename>" "$HOME/Library/Application Support/DeskTidy/desktidy.log" | tail -5
```

Every move is logged as `NAME -> Destination/` with the **final** filename —
including any collision suffix like `report (dup 20260813-141212).md`. The log
is the source of truth; trust it over your memory of where you wrote the file.

## What it does (so you can predict it)

- Watches only the **root** of the target folder. Files inside subfolders are
  never touched — `~/Desktop/Documents/x.pdf` stays put forever.
- Waits until a file has been unmodified for **15 seconds** (and skips
  `.crdownload/.part/.download/.partial/.tmp`), then moves it. Typical time
  from drop to filed: **~20 seconds**; worst case ~75s.
- **Never deletes, never overwrites.** Name collisions keep both files (the
  newcomer gets a `(dup <timestamp>)` suffix, extension preserved).
- Routing (by extension / name prefix):

| Lands in | What |
|---|---|
| `Screenshots/` | names starting `Screenshot ` / `Screen Shot ` |
| `Videos/` | mp4 mov m4v mkv webm avi … + `Screen Recording …` |
| `Images/` | png jpg jpeg heic gif webp svg bmp tiff ico |
| `Audio/` | mp3 wav m4a flac aiff aac ogg |
| `Archives/` | zip tar gz tgz 7z rar dmg pkg iso bz2 xz |
| `Code/` | js ts py rs go swift json yaml sh sql html css c cpp java … |
| `Documents/` | pdf doc(x) txt md rtf pages ppt(x) xls(x) csv epub … |
| `Folders/` | any directory dropped at the root |
| `Inbox/` | anything unrecognized (never guessed into a wrong folder) |

- The user gets a macOS notification for every move. An optional on-device AI
  pass writes suggestions for Inbox items to `Inbox/SMART_TRIAGE_SUGGESTIONS.md`
  — it never moves anything. Do not treat that file as user content.

## Rules for agents

1. **Don't use the watched root as a working directory.** Write working files
   to the project directory or a temp dir. If output must be user-visible on
   the Desktop, prefer `~/Desktop/Inbox/` (DeskTidy never re-sorts inside its
   category folders) or accept that the file will be filed and say so.
2. **If you wrote to the watched root and will read the file again later**,
   either finish within a few seconds, or re-locate it via the log grep above
   before reading. Never conclude a file was lost without checking the log.
3. **Tell the user the final location.** If you leave a file at the watched
   root, expect it to end up in the folder from the table and phrase your
   summary accordingly ("saved to Desktop — DeskTidy will file it under
   Documents"), or check the log after ~25s and report the real path.
4. **For Desktop-heavy tasks** (many files, or a workflow that repeatedly
   rereads files at the root), pause the service first and resume after:

```bash
desktidy teardown        # pause (agents removed; files untouched)
# … do the work …
desktidy setup           # resume  (add --target DIR if it wasn't ~/Desktop)
```

   Only do this for a real need, and always resume. `desktidy status` shows
   the current state, target folder, and recent moves.
5. **Never fight the sorter** — don't move files back to the root and expect
   them to stay, don't edit its log, and don't modify files under
   `~/Library/Application Support/DeskTidy/` other than reading the log.

## Detecting whether DeskTidy is active here

```bash
launchctl print "gui/$(id -u)/com.desktidy.sort" >/dev/null 2>&1 && echo active || echo not-running
```

The target folder is recorded in
`~/Library/LaunchAgents/com.desktidy.sort.plist` (`DESKTIDY_TARGET_DIR`).
The user may have pointed it at `~/Downloads` or another folder instead of the
Desktop — check before assuming.
