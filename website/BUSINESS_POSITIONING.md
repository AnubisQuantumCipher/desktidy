# DeskTidy — Business Positioning

_Source of truth: repo `AnubisQuantumCipher/desktidy` @ `875938e` (v1.1.2). Market research: August 2026._

## The one-sentence position

DeskTidy occupies the empty square on the macOS file-organization board: **free + open-source + local-only + zero-config + never-deletes.**

## The market (verified August 2026)

| Camp | Examples | Price | Their weakness → our wedge |
|---|---|---|---|
| Rules engines | Hazel $42, Spotless $24.99, Declutter $9.99 | one-time | You architect and debug rule sets. DeskTidy works on first run — *"a clean desktop without writing a single rule."* |
| AI organizers | Sparkle $10/mo–$179 lifetime, Sortio, Dynbox | subscription-first | Cloud-touching, model-decides-your-folders trust anxiety. DeskTidy is deterministic, local, inspectable. |
| Cleaners | CleanMyMac $39.95/yr, MacKeeper | subscription | They sell *deletion* and inherit deletion anxiety. DeskTidy **never deletes** — the anti-cleaner. |
| OSS CLI | organize (tfeldmann), Maid | free | YAML/config burden, no UX. DeskTidy is the zero-config one with notifications. |

Premium-indie pricing reference points: Bartender $20, CleanShot X $29 (one-time + optional update renewals — repeatedly praised for NOT being subscriptions).

## Free vs. paid boundary

**DeskTidy Core (free forever, MIT):** the current CLI + background service — sorting engine, notifications, smart-triage suggestions, logs, multi-folder targeting. The free tier IS the trust engine; crippling it would destroy the positioning.

**DeskTidy Pro (planned, not yet for sale):** the native menu-bar app.
- Pause/resume from the menu bar
- Live activity feed ("filed 12 items today")
- **One-click undo** (does not exist today — never claim it does)
- Visual rules editor (rename categories, add extensions, per-folder rules)
- First-run GUI onboarding incl. guided Full Disk Access
- Signed + notarized .dmg (requires Developer ID — currently blocked on Apple Developer account issue)

**Price: $19 one-time** per Mac, CleanShot-style (includes 1 year of updates; optional renewal later if wanted). Rationale: Bartender ($20) is the closest analog — a beloved single-purpose menu-bar utility. $9.99 signals toy; $42 (Hazel) is the ceiling for far more capability; subscriptions would contradict the anti-subscription wedge that IS our differentiation.

**Payment rail:** Stripe (account exists). **Deliberately not wired up yet** — there is no product to charge for, and fabricating a checkout for an unshipped app violates both honesty and the operator's standing rule against agent-created live payment infrastructure. Activate when the menu-bar app is real.

## Conversion model

Primary conversion (today): `brew install` → a working, delightful free product.
Secondary: **early-access email list** (live at desktidy.vercel.app, Neon-backed) → launch audience for Pro.
Tertiary: GitHub stars → social proof + Homebrew tap credibility.

Funnel: Show HN / Reddit → site → install OR early-access → Pro launch email → $19 purchase.

## What must exist before charging anyone

1. The menu-bar app actually built (engine reuse: the Swift core is Pro-ready as-is)
2. Signed + notarized .dmg (Developer ID — **blocked**: the paid membership isn't attached to the Apple ID in Xcode; resolve before any Pro work)
3. Undo implemented (the #1 promised Pro feature)
4. A real license-key mechanism (Paddle/Lemon Squeezy handle keys + global sales tax, or Stripe + a tiny license service)
5. Update mechanism (Sparkle)
6. ≥100 early-access signups OR equivalent launch-audience signal — otherwise the launch email lands in a void

## Success metrics (90 days)

- 500+ GitHub stars (credibility threshold for a Show HN-launched utility)
- 100+ early-access emails (minimum viable launch audience)
- brew installs trending (no telemetry — proxy via tap traffic/stars)
- Zero data-loss reports (the brand IS safety; one incident kills it)
