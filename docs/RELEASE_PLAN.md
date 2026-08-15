# DeskTidy — Reduced Release Plan (dependency-ordered)

_Updated 2026-08-15. Supersedes the implementation ordering implied by earlier roadmap
drafts. Rule: the first native release earns trust before anything earns
breadth. Every feature ships only when its **gate** — an executable check —
passes. Nothing is "done" because it compiles or because an API exists._
 
## Current local deployment boundary

The R2 artifact is an ad-hoc Apple Silicon macOS 14+ local deployment. On the
operator Mac, the authorized transaction migrated `/Users/sicarii/Desktop`
from the retained personal sorter to `com.desktidy.sort` and
`com.desktidy.notify`. Direct readback is `SOLE`, `runningHealthy`,
`targetSource=nativeConfig`, and a valid receipt chain. The former labels and
active plists are absent; byte-verified rollback assets remain retained.

The local deployment is operational and rollback-backed, not a supported public
release, Developer ID-signed/notarized artifact, TestFlight/App Store build, or
public installer. A bounded source-built Homebrew developer preview exists.
Phase N keyboard focus traversal and spoken
VoiceOver output remain **INDETERMINATE**. Historical sacrificial
`SMAppService` evidence still does not prove Login Items/FDA/TCC, reboot, or
login behavior, and no reboot was performed for this seal.

The live transaction and its defects are not presented as a smooth cutover:

1. three fail-closed attempts exposed prior-support, unrelated WatchPath, and
   process-self-match defects before the successful handoff;
2. the first live sweep moved retained `Archive`, `Docs`, `Media`, and
   `Projects` roots; those exact directories were restored and are now
   protected in automatic and manual sweeps;
3. the first actual Undo restored the canary byte-for-byte, then the automatic
   sorter re-filed it two seconds later; one shared process lock plus exact
   durable-Undo suppression fixed the race, and the same canary then completed
   a stable A→B→A cycle.
4. the first native category table exposed `Documents` and `Screenshots` as
   extra Desktop roots; routing policy v2 restores the exact five-root contract
   and permits only traversal-safe nested destinations beneath it.

Full evidence: [`evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md`](evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md).


## R0 — Pre-flight (before any app code) — ✅ IMPLEMENTED 2026-08-14

| Item | Implementation | Gate (executable) |
|---|---|---|
| **Single-mover guard** — one authority per canonical watched root; ordinary setup/start/move paths refuse foreign overlap. The authorized migration path stages while unloaded, re-enumerates launch-agent watchers, boots out the old notifier and sorter before starting the new sorter and notifier, and automatically restores the bound old epoch on failure. | `AuthorityGuard` in [`src/Authority.swift`](../src/Authority.swift) plus plan-first [`scripts/migrate-live.sh`](../scripts/migrate-live.sh); the local cutover is recorded in the deployment receipt | `--r0-test` controls C01–C06 plus `scripts/test-live-migration.sh` fake-substrate ordering, prior-install, foreign-authority, and rollback cases |
| **Canonical receipts** — schema v1, one append-only JSONL ledger with SHA-256 hash chain (unkeyed: integrity evidence, not author authentication), durable prepare→move→complete protocol, deterministic crash reconciliation (`failed` / `recovered` / `indeterminate` — never invented success), and one reader for status/history/Undo | `Receipt`, `ReceiptLedger`, `MovementService` in [`src/Receipts.swift`](../src/Receipts.swift); `--history [n] [--json]`, `--verify-ledger`; full spec in [`R0_AUTHORITY_AND_RECEIPTS.md`](R0_AUTHORITY_AND_RECEIPTS.md) | `--r0-test` controls C07–C19 plus C32–C33; Phase G covers exact Undo, replay, authority, and process-lock behavior |
| **Movement confinement** — sources must be direct non-symlink children of the root; destinations must resolve inside the root; `..`/symlink escapes rejected before any write | `MovementService.validateConfinement` | `--r0-test` controls C20–C23 |
| **ML authority policy adopted** ([ML_AUTHORITY_POLICY.md](ML_AUTHORITY_POLICY.md)) — probabilistic output cannot authorize movement | suggestions lane unchanged (write-only); movement service takes routes only from the deterministic classifier | `--r0-test` control C26 (a hostile suggestion file moves nothing) + C25 (Inbox fallback) |

R0 local-deployment controls: 34 hostile controls green, including compatibility
root retention, stable automatic behavior after Undo, and invalid-ledger
fail-closed behavior. The earlier A→B→A tamper gate was also demonstrated
(guard mutation → C01/C02/C05/C06 fail semantically → byte-exact restore →
green), legacy 17-check self-test unchanged, live coexistence with a foreign
personal mover verified on a real machine without modifying it.

## R1 — The trust release (first native app)

Scope: **one movement authority, observable and reversible.** Nothing else.

| Feature | Prerequisite | Gate |
|---|---|---|
| Menu-bar app skeleton (MenuBarExtra, status = running/paused, live target shown) | R0 receipts | Implemented; state matches shared effective-state and live `launchctl` readback |
| SMAppService registration (spike first: verify replacement semantics + migration from CLI plists on this hardware) | skeleton | Not used for the local deployment; the accepted launchd labels are active, while Login Items and reboot remain unobserved |
| Native notifications (UNUserNotificationCenter): original name, final name, destination, collision suffix, Reveal action | receipts | Notification content equals receipt content in test; delivery failure provably never blocks a move |
| **Undo (single-step)** from receipt: reverse the last move iff source slot is still free; collision-safe; idempotent; refuses honestly otherwise | receipts | Property test: move→undo→bytes identical; undo-after-manual-interference refuses with reason |
| **WhereDidItGo** — answer from receipts + live filesystem verification (size check before answering); plain "another process appears to have moved it" when log is silent | receipts | Test: sorter-moved file → exact path; manually-moved file → honest fallback answer |
| Bounded App Intents: TidyNow, Pause(duration), Resume, Status, RecentMoves, WhereDidItGo | all above | Each intent exercised via `shortcuts run`; mutating intents produce receipts |

**R1 exit bar:** local migration, rollback, app relaunch, service reload, crash
reconciliation fixtures, pause, and Undo are evidenced. The broader bar remains
open for reboot/login and complete keyboard/VoiceOver acceptance.

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
