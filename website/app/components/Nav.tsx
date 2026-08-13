"use client";

import { useEffect, useState } from "react";
import Logo from "./Logo";

const LINKS = [
  { href: "#product", label: "Product" },
  { href: "#how-it-works", label: "How it works" },
  { href: "#safety", label: "Safety" },
  { href: "#faq", label: "FAQ" },
  { href: "https://github.com/AnubisQuantumCipher/desktidy", label: "GitHub", external: true },
];

export default function Nav() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <header
      className="sticky top-0 z-50 border-b"
      style={{
        background: "color-mix(in srgb, var(--bg) 82%, transparent)",
        backdropFilter: "blur(14px)",
        WebkitBackdropFilter: "blur(14px)",
        borderColor: "var(--line)",
      }}
    >
      <nav className="container-site flex h-16 items-center justify-between" aria-label="Main">
        <a href="#top" className="flex items-center gap-2.5 font-semibold tracking-tight">
          <Logo className="h-7 w-7" />
          <span>DeskTidy</span>
        </a>

        {/* desktop links */}
        <div className="hidden items-center gap-7 md:flex">
          {LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="text-sm font-medium transition-colors"
              style={{ color: "var(--fg-soft)" }}
              {...(l.external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
            >
              {l.label}
              {l.external ? <span className="sr-only"> (opens in a new tab)</span> : null}
            </a>
          ))}
          <a href="#install" className="btn-primary !px-4 !py-2 text-sm">
            Install DeskTidy
          </a>
        </div>

        {/* mobile toggle */}
        <button
          type="button"
          className="flex h-10 w-10 items-center justify-center rounded-lg border md:hidden"
          style={{ borderColor: "var(--line)" }}
          aria-expanded={open}
          aria-controls="mobile-menu"
          onClick={() => setOpen((v) => !v)}
        >
          <span className="sr-only">{open ? "Close menu" : "Open menu"}</span>
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true">
            {open ? (
              <path d="M3 3l12 12M15 3L3 15" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            ) : (
              <path d="M2 4.5h14M2 9h14M2 13.5h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            )}
          </svg>
        </button>
      </nav>

      {/* mobile menu */}
      {open && (
        <div
          id="mobile-menu"
          className="border-t px-6 pb-6 pt-3 md:hidden"
          style={{ background: "var(--bg)", borderColor: "var(--line)" }}
        >
          <ul className="flex flex-col gap-1">
            {LINKS.map((l) => (
              <li key={l.href}>
                <a
                  href={l.href}
                  className="block rounded-lg px-3 py-3 text-base font-medium"
                  style={{ color: "var(--fg)" }}
                  onClick={() => setOpen(false)}
                  {...(l.external ? { target: "_blank", rel: "noopener noreferrer" } : {})}
                >
                  {l.label}
                </a>
              </li>
            ))}
            <li className="mt-2">
              <a href="#install" className="btn-primary w-full justify-center" onClick={() => setOpen(false)}>
                Install DeskTidy
              </a>
            </li>
          </ul>
        </div>
      )}
    </header>
  );
}
