# DeskTidy snippet for coding agents

DeskTidy users who run AI coding agents (Claude Code, Codex, Cursor, etc.):
paste the block below into the file your agent reads on every session —
`AGENTS.md`, `CLAUDE.md`, `~/.codex/AGENTS.md`, or equivalent. It stops agents
from "losing" files that DeskTidy files while they work.

Claude Code users can install the richer skill instead:

```bash
mkdir -p ~/.claude/skills/desktidy-awareness
curl -fsSL https://raw.githubusercontent.com/AnubisQuantumCipher/desktidy/main/skills/desktidy-awareness/SKILL.md \
  -o ~/.claude/skills/desktidy-awareness/SKILL.md
```

---

```markdown
## DeskTidy runs on this Mac

A background service (DeskTidy) automatically files loose items at the root of
~/Desktop (or the folder in DESKTIDY_TARGET_DIR of
~/Library/LaunchAgents/com.desktidy.sort.plist) into category subfolders
(Documents, Images, Screenshots, Videos, Audio, Archives, Code, Folders;
unknown → Inbox) about 20 seconds after they stop changing. It never deletes
and never overwrites (collisions get a "(dup <timestamp>)" suffix).

- A file you wrote there that "vanished" was filed, not lost. Find it:
  grep -F "<name>" "$HOME/Library/Application Support/DeskTidy/desktidy.log"
  (the log records the FINAL filename, including any dup suffix).
- Don't use the watched root as a working directory — use the project dir, a
  temp dir, or ~/Desktop/Inbox/ (subfolders are never re-sorted).
- If a task genuinely needs many files at the root: `desktidy teardown` to
  pause, work, then `desktidy setup` to resume. Always resume.
- When you leave a file at the root for the user, tell them where it will be
  filed (or check the log after ~25s and report the real path).
```
