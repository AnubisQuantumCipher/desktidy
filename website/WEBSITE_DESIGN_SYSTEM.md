# DeskTidy Website — Design System

## Brand rationale

The visual identity is built on one moment: **the feeling immediately after a messy desk becomes clean.** Calm, precise, quietly satisfying. Not sterile minimalism, not SaaS-card soup, not "AI product" gradients — a Mac-native sensibility expressed with web-safe means (the visitor's own system font, restrained color, one confident accent).

The logo is an open folder receiving a single file, with a motion trail and a settle-check — order plus one calm movement gesture. Original artwork; no Finder or Apple glyphs.

## Color tokens (defined in `app/globals.css`)

| Token | Light | Dark | Role |
|---|---|---|---|
| `--bg` (porcelain / graphite) | `#fbfbf9` | `#16181d` | page ground (never pure black) |
| `--bg-alt` (mist) | `#f1f2f5` | `#1d2026` | alternating section bands |
| `--card` | `#ffffff` | `#22252c` | raised surfaces |
| `--fg` (ink) | `#1b1e24` | `#f2f3f6` | primary text |
| `--fg-soft` | `#4b5160` | `#b6bac4` | body/secondary text |
| `--fg-faint` | `#7d8496` | `#858b99` | captions, fine print |
| `--sky` | `#2477ff` | `#4a8dff` | THE accent: CTAs, links, folders, focus rings |
| `--mint` | `#12b981` | `#2fd39a` | success, "filed", safety checks |
| `--amber` | `#e8a13d` | `#f0b45c` | Inbox / uncertainty ONLY |
| `--line` | 10% ink | 12% white | hairline borders |

Rules: **one saturated accent** (sky) for everything interactive; mint only for positive completion; amber exclusively marks the Inbox/uncertainty concept — it is the visual embodiment of "unknown means Inbox," never decoration.

Dark mode is automatic via `prefers-color-scheme`, token-swapped, with a `data-theme` escape hatch.

## Typography

- Stack: `-apple-system, BlinkMacSystemFont, "SF Pro Display" …` — renders in San Francisco on Apple devices (the cheapest honest "native" signal; the visitor's own font, no trade-dress issue), graceful elsewhere. No webfont download.
- Mono: `ui-monospace, "SF Mono", Menlo …` for commands only.
- Scale: `.h-display` clamp(2.4–4.2rem, -0.03em tracking) · `.h-section` clamp(1.75–2.6rem) · `.lede` clamp(1.05–1.25rem, 1.6lh) · `.eyebrow` 0.8rem caps +0.12em.
- Weights: 400 / 500 / 600 / 700 only.

## Spacing & shape

- Container: 72rem max, clamp(1.25–2.5rem) gutters. Sections: clamp(4–7.5rem) vertical.
- Radii: 8 / 14 / 22px (cards use 22px; pills are full-round).
- Shadows: two levels only (`--shadow-soft`, `--shadow-lift`), always low-alpha, never glows.

## Components

- **Buttons:** `.btn-primary` (sky pill, white text, 1px hover lift) / `.btn-secondary` (hairline pill). Identical padding, 44px+ touch height.
- **`card-surface`:** the single raised-surface primitive (card bg + hairline + soft shadow + 22px radius).
- **HeroDemo:** fixed-aspect stage (16/10 desktop, 3/4 phones) — absolute-positioned files glide to folder slots via CSS transforms; macOS-style notification card; completion pill; replay. Zero layout shift by construction.
- **BeforeAfter:** clip-path reveal driven by a native range input + explicit Before/After buttons (never drag-only).
- **CopyCommand:** mono command + copy button with ✓ Copied state (mint).
- **FAQ:** native `<details>/<summary>` — zero-JS, keyboard/SR-native.

## Motion rules

- Purposeful only: files travel (700ms, `cubic-bezier(.3,.9,.3,1)` — fast-out, soft-settle), notifications fade/rise (260ms), folder-light-up (400ms). Nothing loops, nothing autoplays continuously.
- **Reduced motion:** global kill-switch (`prefers-reduced-motion: reduce` zeroes all transition/animation durations) plus the demo component checks `matchMedia` and swaps travel animation for instant state changes. The demo remains fully understandable as static before/after states.

## Accessibility rules

- Semantic landmarks; one `h1`; ordered headings; skip-link; `scroll-padding-top` for anchor jumps under the sticky nav.
- Focus: 2.5px sky `:focus-visible` ring, 3px offset, everywhere.
- The animated demo carries `role="img"` with state-dependent labels; decorative layers are `aria-hidden`; progress announced via `aria-live="polite"`.
- Mobile menu: `aria-expanded`/`aria-controls`, Escape closes, body scroll locked while open.
- Contrast: all text tokens ≥ AA on their grounds in both themes.
- Touch targets ≥ 44px; no horizontal overflow from 320px up.

## Voice

Specific, human, lightly witty; never shames the user ("None of it is junk — that's why it's still there"). Banned: revolutionize, seamless, unleash, "AI-powered," "the future of." Safety claims stated as checkable facts with the repo as receipts.
