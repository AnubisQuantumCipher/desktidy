"use client";

import { useId, useState } from "react";

/* Before/after comparison. A range slider (keyboard-native) drives the reveal,
   plus explicit Before/After buttons — never drag-only. */

const MESSY = [
  { glyph: "🖼️", label: "Screenshot 2026-08-10 at 3.09.11 PM.png", x: 6, y: 10 },
  { glyph: "🖼️", label: "Screenshot 2026-08-11 at 9.41.00 AM.png", x: 30, y: 6 },
  { glyph: "📄", label: "contract-FINAL-v3 (2).pdf", x: 58, y: 12 },
  { glyph: "🎬", label: "Screen Recording 2026-08-12.mov", x: 80, y: 8 },
  { glyph: "🗜️", label: "assets-export.zip", x: 12, y: 42 },
  { glyph: "📄", label: "notes copy 4.txt", x: 42, y: 38 },
  { glyph: "⌨️", label: "scratch.py", x: 68, y: 44 },
  { glyph: "❓", label: "untitled folder 2", x: 24, y: 70 },
  { glyph: "🎵", label: "memo.m4a", x: 52, y: 68 },
  { glyph: "📄", label: "IMG_4021.HEIC", x: 78, y: 66 },
];

const TIDY = ["Documents", "Images", "Screenshots", "Videos", "Audio", "Archives", "Code", "Inbox"];

export default function BeforeAfter() {
  const [value, setValue] = useState(50);
  const id = useId();

  return (
    <div>
      <div
        className="card-surface relative w-full overflow-hidden"
        style={{ aspectRatio: "16 / 9" }}
        role="img"
        aria-label="Comparison of the same Mac desktop: the left side shows ten scattered files and folders; the right side shows the same desktop organized into eight labeled folders."
      >
        {/* AFTER layer (base) */}
        <div className="absolute inset-0" style={{ background: "var(--card)" }} aria-hidden="true">
          <div
            className="absolute inset-0"
            style={{ background: "radial-gradient(110% 80% at 80% 10%, var(--mint-wash) 0%, transparent 55%)" }}
          />
          <div className="absolute inset-x-6 top-1/2 grid -translate-y-1/2 grid-cols-4 gap-y-8 sm:inset-x-14">
            {TIDY.map((name) => (
              <div key={name} className="flex flex-col items-center">
                <svg viewBox="0 0 64 48" className="h-10 w-14" role="presentation">
                  <path
                    d="M4 10a5 5 0 0 1 5-5h14l6 6h26a5 5 0 0 1 5 5v22a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5Z"
                    fill={name === "Inbox" ? "var(--amber)" : "var(--sky)"}
                    opacity="0.9"
                  />
                </svg>
                <span className="mt-1 text-[11px] font-medium" style={{ color: "var(--fg-soft)" }}>
                  {name}
                </span>
              </div>
            ))}
          </div>
          <p
            className="absolute bottom-3 left-1/2 -translate-x-1/2 rounded-full px-3 py-1 text-[11px] font-semibold"
            style={{ background: "var(--mint-wash)", color: "var(--mint)" }}
          >
            After — every file still here, just filed
          </p>
        </div>

        {/* BEFORE layer (clipped by slider) */}
        <div
          className="absolute inset-0"
          style={{ clipPath: `inset(0 ${100 - value}% 0 0)`, background: "var(--card)" }}
          aria-hidden="true"
        >
          <div
            className="absolute inset-0"
            style={{ background: "radial-gradient(110% 80% at 15% 10%, var(--amber-wash) 0%, transparent 55%)" }}
          />
          {MESSY.map((f, i) => (
            <div
              key={i}
              className="absolute flex w-24 flex-col items-center text-center"
              style={{ left: `${f.x}%`, top: `${f.y}%`, transform: `rotate(${(i % 3) - 1}deg)` }}
            >
              <span className="text-2xl sm:text-3xl">{f.glyph}</span>
              <span
                className="mt-0.5 max-w-full truncate rounded px-1 text-[9px] sm:text-[10px]"
                style={{ color: "var(--fg-soft)", background: "color-mix(in srgb, var(--bg) 75%, transparent)" }}
              >
                {f.label}
              </span>
            </div>
          ))}
          <p
            className="absolute bottom-3 left-4 rounded-full px-3 py-1 text-[11px] font-semibold"
            style={{ background: "var(--amber-wash)", color: "var(--amber)" }}
          >
            Before — Friday afternoon
          </p>
        </div>

        {/* divider */}
        <div
          aria-hidden="true"
          className="absolute inset-y-0 w-0.5"
          style={{ left: `${value}%`, background: "var(--sky)", boxShadow: "0 0 0 1px rgba(255,255,255,0.4)" }}
        >
          <span
            className="absolute left-1/2 top-1/2 flex h-8 w-8 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full text-[10px] font-bold text-white"
            style={{ background: "var(--sky)", boxShadow: "var(--shadow-lift)" }}
          >
            ⇔
          </span>
        </div>
      </div>

      <div className="mt-4 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
        <button type="button" className="btn-secondary !px-4 !py-2 text-sm" onClick={() => setValue(100)}>
          Show before
        </button>
        <label htmlFor={id} className="flex w-full max-w-xs items-center gap-3">
          <span className="sr-only">Reveal the before / after comparison</span>
          <input
            id={id}
            type="range"
            min={0}
            max={100}
            value={value}
            onChange={(e) => setValue(Number(e.target.value))}
            className="w-full accent-[var(--sky)]"
            aria-valuetext={`${value}% of the messy desktop visible`}
          />
        </label>
        <button type="button" className="btn-secondary !px-4 !py-2 text-sm" onClick={() => setValue(0)}>
          Show after
        </button>
      </div>
    </div>
  );
}
