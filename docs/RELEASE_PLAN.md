# DeskTidy — Reduced Release Plan (dependency-ordered)

_2026-08-14. Supersedes the implementation ordering implied by earlier roadmap
drafts. Rule: the first native release earns trust before anything earns
breadth. Every feature ships only when its **gate** — an executable check —
passes. Nothing is "done" because it compiles or because an API exists._
 
## Current local-RC boundary

The R2 local RC is an ad-hoc Apple Silicon macOS 14+ package tested on
non-Desktop fixtures. It is not a public release, Homebrew update, Developer
ID-signed/notarized artifact, or authorization for live service/Desktop use.
Its Phase N visual/accessibility lane is **INDETERMINATE**, so the release bar
below is not met. Historical sacrificial `SMAppService` evidence does not prove
production migration, Login Items/FDA/TCC, reboot, or login behavior.


## R0 — Pre-flight (before any app code) — ✅ IMPLEMENTED 2026-08-14

| Item | Implementation | Gate (executable) |
|---|---|---|
| **Single-mover guard** — one authority per canonical watched root; every setup/start/move path refuses when a foreign launchd agent watches the same (symlink-resolved, device/inode-compared) root; ambiguity fails closed; takeover is deliberately NOT implemented | `AuthorityGuard` in [`src/Authority.swift`](../src/Authority.swift); wired into engine startup (`DeskTidy.run`), `desktidy setup` (`src/desktidy-cli.sh`), and `install.sh`; diagnose via `desktidy-sort --authority-diagnose [--json]` | `--r0-test` controls C01–C06 (same root, symlink-equivalent root, disjoint allowed, unreadable→fail-closed, stale-vs-loaded, engine refusal exit 2) |
| **Canonical receipts** — schema v1, one append-only JSONL ledger with SHA-256 hash chain (unkeyed: integrity evidence, not author authentication), durable prepare→move→complete protocol, deterministic crash reconciliation (`failed` / `recovered` / `indeterminate` — never invented success), single history reader for status/history and future Undo | `Receipt`, `ReceiptLedger`, `MovementService` in [`src/Receipts.swift`](../src/Receipts.swift); `--history [n] [--json]`, `--verify-ledger`; full spec in [`R0_AUTHORITY_AND_RECEIPTS.md`](R0_AUTHORITY_AND_RECEIPTS.md) | `--r0-test` controls C07–C19 (durability, races, syscall failure, four restart states, malformed intent, digest tamper) |
| **Movement confinement** — sources must be direct non-symlink children of the root; destinations must resolve inside the root; `..`/symlink escapes rejected before any write | `MovementService.validateConfinement` | `--r0-test` controls C20–C23 |
| **ML authority policy adopted** ([ML_AUTHORITY_POLICY.md](ML_AUTHORITY_POLICY.md)) — probabilistic output cannot authorize movement | suggestions lane unchanged (write-only); movement service takes routes only from the deterministic classifier | `--r0-test` control C26 (a hostile suggestion file moves nothing) + C25 (Inbox fallback) |

R0 exit criteria met: 31 hostile controls green, A→B→A tamper gate demonstrated
(guard mutation → C01/C02/C05/C06 fail semantically → byte-exact restore →
green), legacy 17-check self-test unchanged, live coexistence with a foreign
personal mover verified on a real machine without modifying it.

## R1 — The trust release (first native app)

Scope: **one movement authority, observable and reversible.** Nothing else.

| Feature | Prerequisite | Gate |
|---|---|---|
| Menu-bar app skeleton (MenuBarExtra, status = running/paused, live target shown) | R0 receipts | State shown matches `launchctl` truth in a scripted probe |
| SMAppService registration (spike first: verify replacement semantics + migration from CLI plists on this hardware) | skeleton | Old plists removed exactly once; agent survives reboot; Login Items entry visible; rollback script restores CLI mode |
| Native notifications (UNUserNotificationCenter): original name, final name, destination, collision suffix, Reveal action | receipts | Notification content equals receipt content in test; delivery failure provably never blocks a move |
| **Undo (single-step)** from receipt: reverse the last move iff source slot is still free; collision-safe; idempotent; refuses honestly otherwise | receipts | Property test: move→undo→bytes identical; undo-after-manual-interference refuses with reason |
| **WhereDidItGo** — answer from receipts + live filesystem verification (size check before answering); plain "another process appears to have moved it" when log is silent | receipts | Test: sorter-moved file → exact path; manually-moved file → honest fallback answer |
| Bounded App Intents: TidyNow, Pause(duration), Resume, Status, RecentMoves, WhereDidItGo | all above | Each intent exercised via `shortcuts run`; mutating intents produce receipts |

**R1 exit bar:** the [release bar](#release-bar) below passes on a clean Mac,
an upgrade Mac (CLI→app migration), and after crash/reboot/pause cycles.

## R2 — History & findability

| Feature | Prerequisite | Gate |
|---|---|---|
| Activity feed (QuickLook thumbnails) | R1 receipts | Feed reconstructs from receipts alone on fresh launch |
| Core Spotlight donation of receipts (lexical; semantic flag unmarketed) | receipts | Donate→search→delete-on-undo verified; latency measured and stated |
| ControlWidget pause toggle; desktop widget (read-mostly) | R1 intents | Widget state never disagrees with service state in probe script |

## R3 — Intelligence, gated by the authority ladder

| Feature | Ladder level | Prerequisite | Gate |
|---|---|---|---|
| NLEmbedding similarity suggestions | 1 | R1 | Suggestions carry provenance; zero moves in audit log |
| Vision OCR screenshot annotations + rename **suggestions** | 1→2 | R1 notifications (approve button) | OCR text demonstrably never parsed as instructions (injection test file); per-item approval required |
| User-authored OCR keyword rules | 3 | ML policy §Level-3 conditions | Rule off by default; provenance in every receipt; deterministic fallback exercised with model disabled |
| ClassifyImageRequest visual rules | 3 | same | same |
| Foundation Models triage in-app (@Generable typed output; CLI keeps macro-free pipe format) | 1 | R1 | `rateLimited`/unavailable → deterministic path, verified on battery |

## R4 — Distribution maturity

Sparkle 2 (opt-in update check + revised network claim wording), notarized DMG
(**blocked on Developer ID**), Homebrew cask pointing at the same DMG,
Finder Quick Action extension (only if a real workflow demands it — Tier-3 per
review).

## Explicitly not scheduled

FinderSync, Focus filters, FSKit, File Provider, Live Activities, Endpoint
Security, LoRA adapters, macOS-27 multimodal, semantic automatic routing,
universal content inspection. Reasons in [APPLE_NATIVE_ROADMAP.md](APPLE_NATIVE_ROADMAP.md).

## Release bar

A feature is real only when: exact OS/hardware/permission scope stated;
observed on a target Mac; deterministic fallback exercised; unavailable and
denied-permission states tested; move-safety invariants green; crash/restart
and duplicate-service conditions tested; receipts identify the actual mover;
docs match effective state; no suggestion is represented as an executed move;
a reproducible gate exists.
