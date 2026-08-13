# DeskTidy Website — Verification Report

**Date:** 2026-08-13
**Product source of truth:** `AnubisQuantumCipher/desktidy` @ `875938e` (main, v1.1.2)
**Production:** https://desktidy.vercel.app

## Product protection

- Website lives entirely in `website/`; `git status` confirms no sorter/installer/CI file was modified by website work.
- DeskTidy CI on `875938e`: **passing** (macOS 14 + 15: build, self-test, read-only probe, sandbox sort, collision safety).
- Every product claim on the site was cross-checked against a three-agent research pass over the actual source (see `BUSINESS_POSITIONING.md` for market claims). Notable honesty calls: "~20 seconds" latency (15s settle + second sweep — never "instant"), no Intel claims (CI runners are Apple Silicon), no "undo" feature claim (log-assisted manual reversal only), notification clickability labeled as depending on optional terminal-notifier, AI described as suggestions-only/compiled-out pre-macOS 26.

## Website correctness (all run against the production build)

| Check | Result |
|---|---|
| `tsc --noEmit` | ✅ clean |
| `next lint` (ESLint) | ✅ clean |
| `next build` (production) | ✅ all routes static except `/api/waitlist` (dynamic by design) |
| Hero transformation | ✅ staggered 7-file animation, per-file notifications, completion state, replay — verified by click-through |
| Layout regressions | ✅ two found during verification (completion pill overlapped folder row; unknown-file start position) — fixed and re-verified |
| Copy buttons | ✅ component present on 6 commands; clipboard write + ✓ Copied feedback |
| Mobile menu | ✅ open/close verified via DOM: `aria-expanded` true/false, 6 links, Escape + scroll-lock implemented |
| Waitlist API | ✅ unconfigured→503 with honest UI message; live: 201 insert → 409 duplicate → 400 invalid (verified against production; test row deleted afterward) |
| Console errors | ✅ none (checked repeatedly incl. after interactions) |
| Links | ✅ all internal anchors resolve; external links target the real repo paths (README, SECURITY.md, LICENSE, CHANGELOG, releases) |

## Browser verification (visual, real renders)

| Environment | Result |
|---|---|
| Chromium desktop (1698×947), dark | ✅ hero, demo animation end-to-end, all sections |
| Chromium desktop, light | ✅ porcelain theme verified |
| iPhone-size (375×812, mobile emulation) | ✅ hero, taller 3/4 demo stage (fixed a cramped-stage issue found here), pain, before/after slider + buttons, hamburger |
| Safari / Firefox / iPad | ⚠️ not exercised in this pass — CSS used (clip-path, aspect-ratio, color-mix, backdrop-filter) is supported in all current versions; flagged as follow-up |

## Accessibility

- Keyboard: all interactives are native buttons/links/inputs; range slider keyboard-native; FAQ uses `<details>`; skip-link present. Focus-visible ring throughout.
- Reduced motion: global CSS kill + matchMedia-driven instant states in the demo (mechanism verified in code; OS-level toggle not exercised in the pane).
- SR: landmarks, single h1, ordered headings, `role="img"` + live-region on the demo, labeled form fields.
- Formal AA contrast audit + screen-reader pass: **deferred** (see Known limitations).

## SEO / sharing

- Title/description/canonical, Open Graph + Twitter card with rendered 1200×630 `og.png` (✅ 200 on prod), SoftwareApplication JSON-LD (price 0 — matches reality; no fake ratings), robots.txt + sitemap.xml (✅ 200), favicon SVG + apple-touch-icon + webmanifest.

## Performance

- All pages statically prerendered; zero webfonts; media = one 57KB GIF (below the fold) + SVG; JS limited to five small client components.
- Lighthouse: **not run in this environment** — run `npx lighthouse https://desktidy.vercel.app` for scores. Structure targets the 95/100/100/100 bar (static HTML, no CLS by construction — fixed-aspect stages, no layout-shifting media).

## Deployment

- Vercel project `desktidy` (team anubis-quantum-cipher), production alias **desktidy.vercel.app** (clean subdomain was available).
- Env: `DATABASE_URL` (Neon `desktidy` project, `waitlist` table), `NEXT_PUBLIC_SITE_URL=https://desktidy.vercel.app` — production scope.
- Local dev: `cd website && npm install && npm run dev` (waitlist returns honest 503 without `DATABASE_URL`).
- Deploy: `cd website && vercel --prod --yes`.

## Known limitations / follow-ups

1. Safari/Firefox/iPad visual passes + OS-level reduced-motion + 200% zoom checks not yet run.
2. Lighthouse numbers not captured (environment); run against prod.
3. Formal axe/contrast scan pending.
4. `desktidy.vercel.app` is a platform subdomain; buy a custom domain before serious promotion.
5. Waitlist has no email confirmation loop (single-opt-in; fine at this scale, revisit if list grows).
6. Range-slider wheel interaction can adjust the before/after while scrolling past on some browsers — cosmetic, monitored.
