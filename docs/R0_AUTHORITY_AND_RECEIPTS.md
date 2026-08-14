# R0 — Single Movement Authority & Canonical Receipts

_Implemented 2026-08-14 (v1.2.0). Verified by `desktidy-sort --r0-test`
(31 hostile controls) plus the 17-check `--self-test`._

## 1. The authority model

**Invariant: exactly one movement authority per canonical watched root.**

- The root is canonicalized with `realpath` and compared by device+inode, so
  symlinked aliases of the same folder cannot smuggle in a second authority.
- Every plist in the user's LaunchAgents directory is examined; any agent whose
  `WatchPaths`/`QueueDirectories` overlap the canonical root is classified:

| State | Meaning | Blocks DeskTidy? |
|---|---|---|
| `running` | loaded, live process | **yes** |
| `loadedIdle` | loaded, idle | **yes** |
| `notLoaded` | plist on disk, valid executable, not loaded (would start at login) | **yes** |
| `stale` | plist on disk, executable missing, not loaded | no (reported) |
| `uninspectable` | unreadable/undecodable plist | **fail closed** |

- DeskTidy's own labels (`com.desktidy.sort`, `com.desktidy.notify`) are never
  foreign. Anything else that can move entries from the root — now or at next
  login — produces **CONFLICT**; anything unprovable produces **AMBIGUOUS**;
  both refuse movement. Disjoint roots are proven disjoint and allowed.
- **Takeover is deliberately not implemented.** The guard reports the exact
  conflicting label, plist path, program, and watched root, and tells the user
  to use the other service's own teardown or a disjoint `--target`. A
  migration/takeover flow is a separate, explicitly-authorized future mission.

**Entry points proven to converge on the guard** (control C06 + CI grep):

1. `desktidy-sort` engine start — every launchd wake and every manual run
   (`sort-now`) passes `AuthorityGuard.evaluate` before any move (exit 2
   conflict / exit 3 ambiguous);
2. `desktidy setup` (Homebrew CLI) — `--authority-check` before agents install;
3. `./install.sh` (repo lane) — same check before agents install;
4. `desktidy-sort --authority-diagnose [--json]` — read-only dry-run diagnosis.

Testability: `DESKTIDY_AGENTS_DIR` overrides the plist directory and
`DESKTIDY_LAUNCHD_STATE_FILE` supplies fixture load-states, so the guard is
fully testable without touching live launchd.

## 2. The receipt ledger

One schema (v1), one ledger, one reader.

- **Ledger:** `~/Library/Application Support/DeskTidy/receipts/ledger.jsonl`,
  append-only JSONL, fsync'd writes.
- **Pending intents:** `receipts/pending/<id>.json`, written atomically and
  fsync'd **before** any move.
- **Reader:** `ReceiptLedger.readAll()` — the only history parser; drives
  `--history`, `desktidy status`, and future Undo/`WhereDidItGo`. The
  human-readable `desktidy.log` remains a *view* for the notifier; the ledger
  is *truth* (control C30 proves a dead notifier cannot alter it).

**Schema v1 fields:** `schema`, `id`, `preparedAt`, `completedAt`,
`moverLabel`, `moverVersion`, `rootCanonical`, `sourceRel`, `plannedDestRel`,
`finalDestRel`, `ruleID` (e.g. `ext:pdf`, `prefix:screenshot`,
`fallback:inbox`), `rulePolicyVersion`, `settleMTime`, `settleAgeSeconds`,
`collision`, `outcome`, `failureCode`, `undoEligible`, `prevDigest`, `digest`.
No file contents, previews, or secrets — ever.

**Hash chain:** each record binds `prevDigest` and its own SHA-256 over a
canonical serialization; `--verify-ledger` walks the chain. The chain is
**unkeyed**: it is integrity/identity evidence (detects tampering, truncation,
reordering of history) — it is **not** author authentication, since anyone
with write access could rebuild a consistent chain.

## 3. The movement state machine

```
            ┌──────────── confinement rejected ──────────► failed (receipt)
 classify ──► validate ──► PREPARE intent (fsync)
                              │  persist fails ──────────► no move, no receipt-of-success
                              ▼
                           MOVE (no-overwrite rename;
                           race → re-plan name once)
                              │  syscall fails ──────────► failed (receipt, source intact)
                              ▼
                           COMPLETE (fsync ledger append,
                           pending intent removed)
                              │  append fails ───────────► pending retained; reconciled next start
                              ▼
                            moved
```

**Crash reconciliation** (`startupReconcile`, runs before every sweep) replays
pending intents against filesystem truth:

| Source | Planned dest | Outcome |
|---|---|---|
| present | absent | `failed` / `crash_before_move` (file will be re-swept) |
| absent | present | `recovered` (move happened; undo-eligible) |
| present | present | `failed` / `crash_before_move_dest_occupied` (never claims the foreign file) |
| absent | absent | `indeterminate` / `state_unprovable` — success is never invented |
| malformed intent | — | quarantined `corrupt-*` + `indeterminate` marker receipt |

## 4. Confinement

Movement refuses, before writing anything: sources that are not direct
children of the canonical root; `.`/`..`/path-traversal names; symlink
sources; destination directories that are symlinks or resolve outside the
root. Every refusal is itself receipted (`confinement_rejected`).

## 5. What R0 does not do (recorded non-goals)

- No takeover/migration of a conflicting authority (future authorized mission).
- No Undo command yet — receipts carry the inverse metadata (`undoEligible`,
  final paths) that R1's Undo will consume.
- The notifier still tails `desktidy.log`; pointing it at the ledger is R1
  backlog (see `R0_BACKLOG.md`).
