"use client";

import { useRef, useState } from "react";

export default function CopyCommand({ command, label }: { command: string; label?: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), 2200);
    } catch {
      /* clipboard unavailable (permissions/http) — select-able text remains */
    }
  };

  return (
    <div
      className="flex items-center gap-2 rounded-xl border p-1.5 pl-4"
      style={{ background: "color-mix(in srgb, var(--fg) 4%, var(--card))", borderColor: "var(--line)" }}
    >
      <code
        className="min-w-0 flex-1 overflow-x-auto whitespace-nowrap py-1.5 text-[13px] sm:text-sm"
        style={{ fontFamily: "var(--font-mono)", color: "var(--fg)" }}
      >
        {command}
      </code>
      <button
        type="button"
        onClick={copy}
        className="shrink-0 rounded-lg px-3 py-2 text-xs font-semibold transition-colors"
        style={{
          background: copied ? "var(--mint-wash)" : "var(--sky-wash)",
          color: copied ? "var(--mint)" : "var(--sky)",
        }}
        aria-label={copied ? "Copied" : `Copy command${label ? `: ${label}` : ""}`}
      >
        {copied ? "✓ Copied" : "Copy"}
      </button>
    </div>
  );
}
