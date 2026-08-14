# DeskTidy × macOS Tahoe — Apple-Native Roadmap

_Research date: 2026-08-14, against macOS 26.x ("Tahoe") and the Xcode 26 SDK.
Every verdict was made against DeskTidy's non-negotiables: never deletes, never
overwrites, local-only, AI suggests-only, unknown→Inbox, everything logged,
honest claims._

## The keystone finding: App Intents

One medium-sized piece of work — five or six intents (`TidyNow`,
`PauseTidying(duration)`, `ResumeTidying`, `SortingStatus`, `UndoLastMove`,
`WhereDidItGo(filename)`) — simultaneously lights up:

- **Spotlight actions with auto-assigned quick keys** (type `td` ⏎ to sweep)
- **Shortcuts actions** (compose with Tahoe's new folder automations)
- **Siri**
- **Control Center / menu-bar Controls** (a pinnable Pause toggle)
- **Widget buttons** (a "Sort now" button on a desktop widget)
- **Apple's MCP bridge (macOS 26.1+)** — intents become drivable by AI agents,
  which extends DeskTidy's existing agent-awareness story from "agents can read
  our log" to "agents can operate us safely"

The new **`UndoableIntent`** protocol maps exactly onto the move log: undo
becomes system-native. **Interactive snippets** let a Spotlight result show
"Moved 3 files → Screenshots, Documents **[Undo]**" with a live button.

Constraint: intents require an .app bundle. The bare CLI can't register them —
which is itself the strongest technical argument for shipping the menu-bar app.

## Adopt NOW (CLI lane, before the app)

| What | Why | Effort |
|---|---|---|
| **Catch `rateLimited` in smart triage** | FoundationModels rate-limits *background processes on battery* — our launchd agent is one. Catch → degrade to unknown→Inbox → log "AI throttled". Currently an unhandled failure lane. | small |
| **Vision OCR on screenshots → deterministic rules** | `RecognizeTextRequest` reads each screenshot locally; the text feeds *user-visible deterministic rules* ("contains 'invoice' → Documents") and content-aware rename *suggestions*. ML output feeding deterministic rules keeps the safety story intact. The single highest-value product upgrade available on every macOS 26 Mac. | medium |
| **NLEmbedding similarity suggestions** | LLM-free second triage engine: embed filename tokens, compare to per-folder centroids. Near-deterministic, no rate limits, no token budget. Better always-on default; reserve the LLM for the ambiguous tail. | small |
| **`desktidy decorate` (Tahoe folder colors + emoji icons)** | Tag destination folders with colors and emoji (📸 🎬 📥…) via xattrs so an organized Desktop *looks* organized. Feature-flag it: the icon xattr format is observed, not documented — fail soft. | small |
| **Documented Shortcuts sample automation** | Tahoe's "when file saved to folder → run shortcut" can invoke `desktidy sort-now` — an onboarding path and a nod to power users. | small |
| **Universal-binary stance** | Tahoe is the last Intel macOS. CLI stays universal (brew builds native). App: universal at launch, arm64-only when the floor moves to macOS 27. | small |
| **Lock the distribution decision** | DeskTidy cannot be sandboxed (background agent, cross-folder moves) ⇒ Developer ID + hardened runtime + notarized DMG, outside the App Store. Same lane as Hazel. Stop revisiting. | — |

## The menu-bar app spec (what the $19 product now is)

Born-Tahoe native, in adoption order:

1. **MenuBarExtra (SwiftUI)** skeleton, `.window` style — template SF Symbol
   status icon (Tahoe's menu bar is transparent; filled variant = paused).
   Liquid Glass for free from the 26 SDK. Icon authored in **Icon Composer**.
   Known paper cuts: open Settings via explicit window, wrap `NSStatusItem`
   if right-click quick actions are wanted.
2. **SMAppService** replaces hand-installed launchd plists — DeskTidy appears
   as a toggleable Login Item in System Settings. Migration: detect + remove
   old CLI plists on first run.
3. **UNUserNotificationCenter** — native notifications *as DeskTidy* with
   **Undo** and **Open in Finder** action buttons. Retires terminal-notifier
   when the app is present (CLI keeps it as fallback).
4. **App Intents suite** (the keystone above) + `UndoableIntent` + interactive
   snippets.
5. **Core Spotlight donation** of move-log entries — "where did my file go?"
   answered from Spotlight itself. Lexical donation only in marketing; the
   semantic flag ships quietly (documented unreliability).
6. **Finder Quick Action** — right-click any file anywhere: "File this with
   DeskTidy." Extends the engine beyond the watch folder with zero new
   watchers; same log, same undo.
7. **QuickLook thumbnails** in the activity feed / undo list (cache-bust by
   mtime — known Tahoe stale-thumbnail report).
8. **ClassifyImageRequest visual rules** — user-authored, threshold-gated,
   clearly ML-labeled ("images classified `receipt` ≥0.8 → Documents/Scans").
9. **@Generable guided generation** for triage in the app build (typed
   `{category enum, confidence, reason}` — the enum makes inventing a folder
   impossible). The CLI keeps the macro-free pipe format — that split is
   deliberate: Homebrew's build environment can't compile the macros.
10. **v1.x:** ControlWidget (Control Center pause toggle), WidgetKit desktop
    widget ("Tidied 47 files this week" + Sort-now button) — both nearly free
    once intents exist.
11. **Sparkle 2** for updates, appcast hosted on desktidy.vercel.app.
    ⚠ Honesty adjustment required: the update check is a network call. New
    claim wording: **"Your files never leave your Mac. The only network call
    is the update check — off by default, opt-in."**

## Deliberate skips (so we stop revisiting them)

- **FoundationModels LoRA adapters** — 160MB+ asset downloads violate the
  zero-network posture; per-OS-version retraining treadmill for a one-person
  studio. Guided generation over a 9-way enum already covers the task.
- **macOS 27 multimodal FoundationModels / Spotlight RAG** — beta-only, gated
  to next-gen hardware; building on it would make claims false for most of
  the install base. Vision OCR delivers the value today. Also: add a lint
  that only the on-device `SystemLanguageModel` is ever constructed — the
  coming provider-abstraction layer is a silent zero-network-violation trap.
- **FinderSync extension** — Apple visibly churned this surface; Quick
  Actions deliver Finder presence without the fragility.
- **Focus filters** — flakiest API on the list (documented perform-not-called
  reports); DND already suppresses banners; PauseTidying intent covers it.
- **FSKit / File Provider** — DeskTidy mounts nothing and syncs nothing. One
  operational note kept: treat dataless cloud-materialized files
  conservatively (settle window already helps; never force-download).
- **Endpoint Security events** — entitlement DeskTidy can't reasonably get +
  a system-extension install flow that kills the lightweight story. FSEvents
  + WatchPaths + settle window is validated as still-correct on Tahoe.
- **Live Activities** — not available to Mac-native apps on Tahoe.
- **Image Playground / Genmoji, Speech transcription** — no honest fit; a
  voice-memo-named-by-first-sentence rename is parked in the backlog.

## Strategic reads

1. **Apple shipped the trigger half of DeskTidy** (Shortcuts folder
   automations) but not the engine: no rules, no settle window, no collision
   safety, no log, no undo. Positioning: compose *with* Shortcuts, differentiate
   on the engine.
2. **Apple did not sherlock desktop filing.** Tahoe's AI touches messages,
   reminders, and search rank — not the file pile. "macOS still won't clean
   your Desktop. DeskTidy does — locally, deterministically" stays honest.
3. **MCP-over-App-Intents makes the agent story compound.** DeskTidy is
   already the only organizer with an agent-awareness skill; intents make it
   the only one agents can *safely drive*. Same $19 app, second audience.
