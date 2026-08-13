# DeskTidy

**Your macOS Desktop, organized automatically.** Drop anything on your Desktop and DeskTidy files it into the right folder within seconds — and shows you a clickable notification telling you where it went. No dragging, no thinking, no maintenance.

Built for people whose Desktop turns into a landfill of screenshots, downloads, and half-named files by Friday.

<!-- Add a screen recording here: docs/demo.gif -->

```
Before                          After
────────────                    ────────────
Screenshot 3.09.11 PM.png       📁 Screenshots
invoice_final_v2.pdf            📁 Documents
demo (13s).mp4                  📁 Videos
project-backup.zip              📁 Archives
main.rs                         📁 Code
untitled-2.xyz                  📁 Inbox   ← anything it's unsure about
```

---

## What it does

- **Watches your Desktop** and files each loose item into a type folder — `Documents`, `Images`, `Screenshots`, `Videos`, `Audio`, `Archives`, `Code`, `Folders`, and `Inbox` for anything it can't confidently place.
- **Tells you in real time.** Every move fires a macOS notification — *"📥 Filed to Documents — invoice.pdf"* — and **clicking it opens Finder with that file highlighted.**
- **Runs itself forever.** Installed as a `launchd` agent, so it starts automatically at every login and needs zero babysitting.
- **Optionally uses on-device AI** (macOS 26+, Apple Intelligence) to *suggest* homes for whatever lands in `Inbox` — privately, on your Mac, and only as suggestions.

## Why it's safe

- **It never deletes anything.** DeskTidy only *moves* files. If a name already exists in the destination, it keeps both (adds a timestamp) — it never overwrites.
- **It waits before touching a file** (15s by default), so it never grabs something mid-download or mid-save.
- **The AI never moves anything.** The optional smart pass writes suggestions to a file. You decide.
- **Nothing leaves your Mac.** No servers, no telemetry, no network. The AI is Apple's on-device model.
- **Every move is logged**, so you can always see (and undo) exactly what happened.

---

## Requirements

- macOS 12 (Monterey) or later.
- Apple's command-line developer tools (the installer tells you how if they're missing: `xcode-select --install`).
- *Optional:* [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) (`brew install terminal-notifier`) for **clickable** banners. Without it you still get banners, just not clickable.
- *Optional:* macOS 26+ for the on-device AI triage. On older macOS it's simply skipped.

## Install

```bash
git clone https://github.com/YOUR-USERNAME/desktidy.git
cd desktidy
./install.sh
```

The installer builds DeskTidy locally, loads it, and walks you through the one-time **Full Disk Access** grant (a background helper can't touch your Desktop until you allow it once). That's it.

Want it to organize a different folder instead of the Desktop?

```bash
./install.sh --target ~/Downloads
```

## Uninstall

```bash
./uninstall.sh
```

Removes the tool completely. **Your folders and every file it ever sorted stay exactly where they are** — it only removes DeskTidy itself.

---

## How it works

```
 file lands on Desktop
        │
        ▼
 launchd WatchPaths fires ──► desktidy-sort ──► waits 15s (settle) ──► moves to the right folder ──► logs the move
                                                                                                        │
 desktidy-notify tails the log ─────────────────────────────────────────────────────────────────────►─┘
        │
        ▼
 clickable macOS notification: "📥 Filed to Documents — invoice.pdf"
```

- **`desktidy-sort`** — a small, signed Swift binary. Pure, deterministic rules (extension + a couple of name heuristics). A single-instance lock keeps the watcher and any manual run from colliding.
- **`desktidy-notify.sh`** — a tiny shell watcher that turns each logged move into a notification.
- **Two `launchd` agents** in `~/Library/LaunchAgents/` (`com.desktidy.sort`, `com.desktidy.notify`) — this is what makes it survive reboots. They start at login, watch the folder, and relaunch themselves if needed.

## The folder scheme

| Folder | Gets |
|---|---|
| **Screenshots** | files named `Screenshot …` / `Screen Shot …` |
| **Images** | png, jpg, heic, gif, webp, svg, … |
| **Videos** | mp4, mov, mkv, `Screen Recording …`, … |
| **Audio** | mp3, wav, m4a, flac, … |
| **Documents** | pdf, docx, txt, md, pages, xlsx, csv, epub, … |
| **Code** | js, ts, py, rs, go, swift, json, yaml, sh, … |
| **Archives** | zip, tar, gz, dmg, pkg, … |
| **Folders** | any folder you drop on the Desktop |
| **Inbox** | anything it can't confidently place (never a wrong guess) |

## Configuration

Everything you'd want to change lives in [`src/Config.swift`](src/Config.swift): folder names, which extensions go where, the settle delay, and the AI toggle. Edit it, then re-run `./install.sh` to rebuild and reload.

```swift
static let folderDocuments = "Documents"      // rename freely
static let settleSeconds: TimeInterval = 15   // how long to wait before moving
static let codeExts: Set<String> = ["js","ts","py","rs", …]   // move extensions between sets
```

## Optional: on-device AI triage (macOS 26+)

If you're on macOS 26 with Apple Intelligence, DeskTidy uses Apple's **on-device** foundation model to read the name and a short local preview of files sitting in `Inbox`, then writes `Inbox/SMART_TRIAGE_SUGGESTIONS.md` recommending where each belongs.

It is **suggestions only** — the model never moves, renames, uploads, or deletes anything, and file contents are treated as untrusted (it won't follow instructions hidden inside a file). On older macOS this feature is compiled out entirely; the deterministic sorter is unaffected.

---

## FAQ

**Does it survive a reboot?** Yes. The agents auto-start at every login (they can't run at the lock screen — they need your session — but they're live within seconds of you logging in).

**Why does it need Full Disk Access?** macOS protects the Desktop folder. A background helper can't read or move files there until you allow it once in System Settings. DeskTidy asks for nothing else, and makes no network connections.

**Will it move files I'm actively working on?** No — it waits until a file has been untouched for 15 seconds (configurable), and it skips in-progress downloads (`.crdownload`, `.part`, `.tmp`, …).

**Can I organize my Downloads / another folder instead?** Yes: `./install.sh --target ~/Downloads`.

**What if two files have the same name?** Both are kept. The second gets a `(dup …)` timestamp suffix. Nothing is ever overwritten.

## Roadmap

- Menu-bar app with pause/resume and a live activity feed.
- Per-folder rules and user-defined categories via a JSON config (no rebuild).
- Optional "smart move" mode that acts on high-confidence AI suggestions (opt-in).
- Homebrew tap for one-line install.

## Contributing

Issues and PRs welcome. The whole thing is ~600 lines of Swift plus two small shell scripts — easy to read and hack on. Run `desktidy-sort --self-test` after changes.

## License

MIT — see [LICENSE](LICENSE).

---

*DeskTidy runs entirely on your Mac. It has no servers, no analytics, and no network access of any kind.*
