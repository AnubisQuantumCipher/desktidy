# DeskTidy — Reduced Release Plan (dependency-ordered)

_2026-08-14. Supersedes the implementation ordering implied by earlier roadmap
drafts. Rule: the first native release earns trust before anything earns
breadth. Every feature ships only when its **gate** — an executable check —
passes. Nothing is "done" because it compiles or because an API exists._

## R0 — Pre-flight (before any app code)

| Item | Gate (executable) |
|---|---|
| **Single-mover guard** — `desktidy setup` detects another watcher on the same root (foreign launchd plist with matching WatchPaths, or a known predecessor label) and warns/refuses | Test: install a dummy plist watching the target → `setup` must refuse; remove it → `setup` proceeds |
| **Canonical receipt schema** — one structured move record (original name, final name, final path, rule that fired, timestamp, collision flag, mover identity, stable receipt ID); log remains append-only text + adds a machine-readable sidecar | Round-trip test: every CI sandbox move produces a receipt that reconstructs the final path byte-for-byte |
| **ML authority policy adopted** ([ML_AUTHORITY_POLICY.md](ML_AUTHORITY_POLICY.md)) | CI grep-gate: no ML symbol reachable from the move path |

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
