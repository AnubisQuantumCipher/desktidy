/* The DeskTidy mark: an open folder with one file settling into place —
   order + a single calm movement gesture. Original artwork, no Apple glyphs. */
export default function Logo({ className = "h-8 w-8" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className} role="img" aria-label="DeskTidy logo" fill="none">
      <rect x="4" y="14" width="56" height="42" rx="10" fill="var(--sky)" />
      <path d="M4 24a10 10 0 0 1 10-10h10.5l5 6H60v4H4Z" fill="var(--sky-deep)" opacity="0.55" />
      {/* file gliding in */}
      <rect x="26" y="26" width="12" height="15" rx="2.5" fill="#fff" />
      <path d="M29 31h6M29 34.5h6M29 38h4" stroke="var(--sky)" strokeWidth="1.6" strokeLinecap="round" />
      {/* motion trail */}
      <path d="M20 22c1.8-3.2 4.4-5.6 8-7" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" opacity="0.85" />
      <path d="M15 25c1.2-2.2 2.8-4 5-5.6" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" opacity="0.45" />
      {/* settle check */}
      <path d="M42 46l4 4 8-9" stroke="#fff" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
