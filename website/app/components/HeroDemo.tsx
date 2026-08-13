"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/* The interactive hero: a simulated Mac desktop that tidies itself.
   - "Tidy my Desktop" plays a ~6s staggered transformation
   - each file glides to its destination folder; a notification confirms it
   - unknown file goes to Inbox (amber) — the honesty beat
   - fully keyboard operable; respects prefers-reduced-motion (instant states)
   - absolute positioning inside a fixed-aspect stage → zero layout shift */

type DemoFile = {
  id: string;
  label: string;
  glyph: string;
  dest: string;
  /* start position (% of stage) */
  x: number;
  y: number;
  inbox?: boolean;
};

const FILES: DemoFile[] = [
  { id: "shot", label: "Screenshot 3.09.11 PM.png", glyph: "🖼️", dest: "Screenshots", x: 8, y: 16 },
  { id: "pdf", label: "invoice_final_v2.pdf", glyph: "📄", dest: "Documents", x: 38, y: 8 },
  { id: "mov", label: "demo (13s).mp4", glyph: "🎬", dest: "Videos", x: 68, y: 18 },
  { id: "zip", label: "project-backup.zip", glyph: "🗜️", dest: "Archives", x: 16, y: 46 },
  { id: "rs", label: "main.rs", glyph: "⌨️", dest: "Code", x: 52, y: 38 },
  { id: "wav", label: "voice-memo.m4a", glyph: "🎵", dest: "Audio", x: 80, y: 46 },
  { id: "xyz", label: "untitled-2.xyz", glyph: "❓", dest: "Inbox", x: 30, y: 50, inbox: true },
];

const FOLDERS = ["Documents", "Screenshots", "Videos", "Audio", "Archives", "Code", "Inbox"];

/* destination folder slot positions (% of stage) — a tidy row near the bottom */
function folderPos(index: number): { x: number; y: number } {
  const perRow = 4;
  const row = Math.floor(index / perRow);
  const col = index % perRow;
  const rowCount = Math.ceil(FOLDERS.length / perRow);
  const width = 88;
  const start = (100 - width) / 2 + 6;
  const step = width / perRow;
  return { x: start + col * step, y: rowCount === 1 ? 76 : 60 + row * 18 };
}

const STEP_MS = 650;

export default function HeroDemo() {
  const [phase, setPhase] = useState<"messy" | "tidying" | "tidy">("messy");
  const [movedCount, setMovedCount] = useState(0);
  const [reducedMotion, setReducedMotion] = useState(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const liveRef = useRef<HTMLParagraphElement>(null);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReducedMotion(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);

  const clearTimers = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };

  const tidy = useCallback(() => {
    if (phase === "tidying") return;
    clearTimers();
    if (reducedMotion) {
      setMovedCount(FILES.length);
      setPhase("tidy");
      return;
    }
    setPhase("tidying");
    setMovedCount(0);
    FILES.forEach((_, i) => {
      timers.current.push(
        setTimeout(() => setMovedCount(i + 1), 400 + i * STEP_MS)
      );
    });
    timers.current.push(
      setTimeout(() => setPhase("tidy"), 400 + FILES.length * STEP_MS + 600)
    );
  }, [phase, reducedMotion]);

  const reset = useCallback(() => {
    clearTimers();
    setMovedCount(0);
    setPhase("messy");
  }, []);

  useEffect(() => () => clearTimers(), []);

  const currentNote =
    phase === "tidying" && movedCount > 0 && movedCount <= FILES.length
      ? FILES[movedCount - 1]
      : null;

  return (
    <div className="w-full">
      {/* the stage */}
      <div
        className="card-surface demo-stage relative w-full overflow-hidden"
        style={{ borderRadius: "var(--radius-l)" }}
        role="img"
        aria-label={
          phase === "tidy"
            ? "Simulated Mac desktop, now tidy: every file filed into labeled folders. Nothing was deleted."
            : "Simulated Mac desktop scattered with files: a screenshot, an invoice PDF, a video, an archive, a code file, an audio memo, and one unknown file."
        }
      >
        {/* menu bar */}
        <div
          className="absolute inset-x-0 top-0 z-10 flex h-7 items-center justify-between px-3 text-[11px] font-medium"
          style={{ background: "color-mix(in srgb, var(--fg) 6%, transparent)", color: "var(--fg-soft)" }}
          aria-hidden="true"
        >
          <span> DeskTidy demo</span>
          <span suppressHydrationWarning>{phase === "tidy" ? "0 loose files" : `${FILES.length - movedCount} loose files`}</span>
        </div>

        {/* wallpaper wash */}
        <div
          aria-hidden="true"
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(120% 90% at 20% 0%, var(--sky-wash) 0%, transparent 55%), radial-gradient(100% 80% at 90% 100%, var(--mint-wash) 0%, transparent 50%)",
          }}
        />

        {/* files */}
        {FILES.map((f, i) => {
          const moved = movedCount > i || phase === "tidy";
          const destIndex = FOLDERS.indexOf(f.dest);
          const dest = folderPos(destIndex);
          return (
            <div
              key={f.id}
              aria-hidden="true"
              className="absolute flex w-24 -translate-x-1/2 flex-col items-center text-center sm:w-28"
              style={{
                left: `${moved ? dest.x : f.x + 6}%`,
                top: `${moved ? dest.y - 4 : f.y}%`,
                opacity: moved ? 0 : 1,
                transform: `translateX(-50%) scale(${moved ? 0.35 : 1}) rotate(${moved ? 0 : (i % 3) - 1}deg)`,
                transition: reducedMotion
                  ? "none"
                  : `left 700ms cubic-bezier(.3,.9,.3,1) , top 700ms cubic-bezier(.3,.9,.3,1), opacity 620ms ease ${moved ? "120ms" : "0ms"}, transform 700ms cubic-bezier(.3,.9,.3,1)`,
              }}
            >
              <span className="text-3xl sm:text-4xl" style={{ filter: "saturate(0.92)" }}>
                {f.glyph}
              </span>
              <span
                className="mt-1 max-w-full truncate rounded px-1 text-[10px] leading-tight sm:text-[11px]"
                style={{ color: "var(--fg-soft)", background: "color-mix(in srgb, var(--bg) 70%, transparent)" }}
              >
                {f.label}
              </span>
            </div>
          );
        })}

        {/* destination folders */}
        {FOLDERS.map((name, i) => {
          const pos = folderPos(i);
          const filedHere =
            (phase === "tidy" || movedCount > 0) &&
            FILES.some((f, fi) => f.dest === name && (movedCount > fi || phase === "tidy"));
          const isInbox = name === "Inbox";
          return (
            <div
              key={name}
              aria-hidden="true"
              className="absolute flex w-20 -translate-x-1/2 flex-col items-center sm:w-24"
              style={{ left: `${pos.x}%`, top: `${pos.y}%` }}
            >
              <svg viewBox="0 0 64 48" className="h-9 w-12 sm:h-11 sm:w-14" role="presentation">
                <path
                  d="M4 10a5 5 0 0 1 5-5h14l6 6h26a5 5 0 0 1 5 5v22a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z"
                  fill={isInbox ? "var(--amber)" : "var(--sky)"}
                  opacity={filedHere ? 0.95 : 0.45}
                  style={{ transition: reducedMotion ? "none" : "opacity 400ms ease" }}
                />
              </svg>
              <span className="mt-0.5 text-[10px] font-medium sm:text-[11px]" style={{ color: "var(--fg-soft)" }}>
                {name}
              </span>
            </div>
          );
        })}

        {/* notification */}
        <div
          aria-hidden="true"
          className="absolute right-3 top-9 z-10 w-56 rounded-xl border p-3 sm:w-64"
          style={{
            background: "var(--card)",
            borderColor: "var(--line)",
            boxShadow: "var(--shadow-lift)",
            opacity: currentNote ? 1 : 0,
            transform: currentNote ? "translateY(0)" : "translateY(-6px)",
            transition: reducedMotion ? "none" : "opacity 260ms ease, transform 260ms ease",
          }}
        >
          <p className="text-xs font-semibold">
            📥 Filed to {currentNote?.dest ?? "…"}
          </p>
          <p className="mt-0.5 truncate text-[11px]" style={{ color: "var(--fg-faint)" }}>
            {currentNote?.label ?? ""}
          </p>
        </div>

        {/* completion overlay */}
        <div
          className="absolute inset-x-0 bottom-0 z-10 flex items-center justify-center pb-2 sm:pb-3"
          style={{
            opacity: phase === "tidy" ? 1 : 0,
            transition: reducedMotion ? "none" : "opacity 500ms ease 200ms",
          }}
          aria-hidden={phase !== "tidy"}
        >
          <p
            className="rounded-full px-4 py-1.5 text-xs font-semibold sm:text-sm"
            style={{ background: "var(--mint-wash)", color: "var(--mint)" }}
          >
            ✓ All {FILES.length} files filed — nothing deleted, nothing lost
          </p>
        </div>
      </div>

      {/* controls + live region */}
      <div className="mt-4 flex flex-wrap items-center justify-center gap-3">
        {phase !== "tidy" ? (
          <button type="button" onClick={tidy} className="btn-primary text-sm" disabled={phase === "tidying"}>
            {phase === "tidying" ? "Tidying…" : "Tidy my Desktop"}
          </button>
        ) : (
          <button type="button" onClick={reset} className="btn-secondary text-sm">
            ↺ Replay the mess
          </button>
        )}
        <p ref={liveRef} aria-live="polite" className="sr-only">
          {phase === "tidy"
            ? "Demo complete. All seven files were filed into folders. Nothing was deleted."
            : phase === "tidying"
              ? `Filing files: ${movedCount} of ${FILES.length} done.`
              : "Demo ready. Activate Tidy my Desktop to watch the files file themselves."}
        </p>
      </div>
      <p className="mt-2 text-center text-xs" style={{ color: "var(--fg-faint)" }}>
        Visual demonstration — sped up. The real DeskTidy waits ~20 seconds so it never grabs a file mid-save.
      </p>
    </div>
  );
}
