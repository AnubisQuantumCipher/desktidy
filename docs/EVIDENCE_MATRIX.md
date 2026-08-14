# Evidence Matrix — Tahoe Findings F01–F35

_Generated 2026-08-14 against macOS 26.6 / Xcode 26 SDK, live probes on Apple Silicon. Method: 6 verification agents; primary-source policy: developer.apple.com/apple.com only count as DOCUMENTED; WWDC videos and press are BELIEVED; local SDK/runtime probes are OBSERVED._

Full per-finding detail (availability, permissions, offline, fail-closed, privacy,
testability, corrections) lives in [`EVIDENCE_MATRIX.json`](EVIDENCE_MATRIX.json).
Epistemic key: **DOCUMENTED** = current primary Apple doc · **OBSERVED** = measured
on a real Mac · **BELIEVED** = reasoned/secondary-sourced · **UNKNOWN** = unresolved.

| ID | Technology | Verdict | Status | Invariants | Primary source |
|---|---|---|---|---|---|
| F01 | FoundationModels — guided generation (@Generable) + tool c | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/foundationmodels/lang |
| F02 | FoundationModels — custom LoRA adapters (adapter training  | REJECT | DOCUMENTED | ⚠ threatened | developer.apple.com/apple-intelligence/foundation-model |
| F03 | FoundationModels — WWDC26 multimodal image input, Spotligh | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/foundationmodels/lang |
| F04 | Vision framework — OCR: RecognizeTextRequest + RecognizeDo | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/vision/recognizedocum |
| F05 | Vision framework — ClassifyImageRequest (image/scene class | ADOPT | OBSERVED | preserved | developer.apple.com/documentation/vision/classifyimager |
| F06 | Core Spotlight — CSSearchableItem donation + CSUserQuery s | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/corespotlight/csuserq |
| F07 | NaturalLanguage — NLEmbedding / NLContextualEmbedding | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/naturallanguage/nlcon |
| F08 | Image Playground / Genmoji (ImagePlayground framework, Ima | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/imageplayground/image |
| F09 | Speech (SpeechAnalyzer / SpeechTranscriber, macOS 26) + So | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/speech/speechanalyzer |
| F10 | QuickLookThumbnailing — QLThumbnailGenerator | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/quicklookthumbnailing |
| F11 | SMAppService (ServiceManagement framework) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/servicemanagement/sma |
| F12 | UNUserNotificationCenter (UserNotifications framework) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/usernotifications/unu |
| F13 | App Intents + Shortcuts + Siri + Spotlight actions (macOS  | ADOPT | DOCUMENTED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F14 | FinderSync extension | DEFER | BELIEVED | preserved | developer.apple.com/documentation/findersync |
| F15 | Finder Quick Actions / Services menu (Action extension) | ADOPT | DOCUMENTED | preserved | support.apple.com/guide/mac-help/mchl97ff9142/mac |
| F16 | Core Spotlight donation (CSSearchableItem / CSSearchableIn | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/corespotlight |
| F17 | Focus modes / Do Not Disturb (INFocusStatusCenter + SetFoc | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/appintents/setfocusfi |
| F18 | MenuBarExtra (SwiftUI) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/SwiftUI/MenuBarExtra |
| F19 | WidgetKit desktop widgets (macOS) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/widgetkit/adding-inte |
| F20 | App Sandbox vs Full Disk Access / TCC UX | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/security/app_sandbox |
| F21 | Sparkle 2 (vs Mac App Store updates) | ADOPT | DOCUMENTED | ⚠ threatened | NONE |
| F22 | Liquid Glass design language (macOS 26) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/technologyoverviews/a |
| F23 | Spotlight redesign: actions, quick keys, clipboard history | ADOPT | DOCUMENTED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F24 | App Intents advances (Spotlight invocation on Mac, Undoabl | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/appintents/undoablein |
| F25 | Shortcuts automations on Mac + intelligent actions (Use Mo | ADOPT | DOCUMENTED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F26 | Foundation Models framework (on-device LLM API) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/foundationmodels |
| F27 | Apple Intelligence user-facing features in Tahoe (Live Tra | DEFER | DOCUMENTED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F28 | Finder folder customization: tag-driven folder colors + em | ADOPT | BELIEVED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F29 | Desktop widgets (WidgetKit on macOS) | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/widgetkit |
| F30 | Controls (ControlWidget) in macOS Tahoe Control Center / m | SPIKE | DOCUMENTED | preserved | developer.apple.com/documentation/swiftui/controlwidget |
| F31 | Live Activities on Mac (ActivityKit) | DEFER | DOCUMENTED | preserved | www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the |
| F32 | FSKit (user-space file systems) | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/fskit |
| F33 | File Provider + NSFileProviderSearching (Tahoe cloud-file  | DEFER | DOCUMENTED | preserved | developer.apple.com/documentation/fileprovider/nsfilepr |
| F34 | File-system event APIs beyond FSEvents / launchd WatchPath | DEFER | BELIEVED | preserved | developer.apple.com/documentation/bundleresources/entit |
| F35 | Intel sunset: Tahoe last Intel macOS; Rosetta wind-down | ADOPT | DOCUMENTED | preserved | developer.apple.com/documentation/macos-release-notes/m |

## Headline corrections applied to the roadmap

- **MCP-over-App-Intents (macOS 26.1)** — no evidence row carries it; sole source was press (9to5Mac). Status: **UNKNOWN**. Struck from the App Intents rationale.
- **UndoableIntent** — *upgraded*: a documented public protocol, macOS 26.0+ (original citation was only a WWDC video). F24.
- **Siri App-Intents actions** — WWDC26 session targets the **27** cycle, not Tahoe; moved out of macOS-26 claims. F13.
- **LLM/semantic Spotlight over donations** — macOS **27** capability; on Tahoe you get lexical donation only; semantic-flag instability itself is forum-sourced (BELIEVED). F16/F06.
- **Folder emoji/color xattr mechanism** — reverse-engineered (eclecticlight.co), not Apple-documented; xattr round-trip OBSERVED locally but Finder rendering unverified → feature-flagged spike, not 'immediately shippable'. F28.
- **FinderSync churn narrative** — blog-sourced (BELIEVED); framework itself documented and not deprecated. F14.
- **Intel sunset** — *upgraded*: now grounded verbatim in Apple's 26.4 release notes (original was MacRumors); the '~2028 security updates' tail remains an inference. F35.
- **Sandbox impossibility / Developer-ID lane** — Apple-documented and DTS-confirmed; only the 'Hazel does the same' comparison is vendor-sourced. F20.
- **FoundationModels battery rate-limiting** — Apple-engineer forum reply, not documentation → BELIEVED; the defensive catch ships anyway. F01.
- **'~3B parameters'** — WWDC video only → BELIEVED; removed from marketing-grade claims. F01.
- **Model changes at 26.4/27.0** — newly surfaced from Apple's updates page: prompts must be re-tested per OS model version. F01.
- **Shortcuts 'Run Shell Script'** requires an explicit Allow-Running-Scripts opt-in the roadmap omitted. F25.
