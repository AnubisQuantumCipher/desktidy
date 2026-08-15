const QA: { q: string; a: string }[] = [
  {
    q: "Is DeskTidy publicly available?",
    a: "No. The repository currently contains an ad-hoc local release candidate, not a public installer, Homebrew release, Developer ID-signed app, or notarized download.",
  },
  {
    q: "What has been verified?",
    a: "Fixture-root contracts cover guarded movement, receipts, notifications, Undo, history, bounded App Intents, lifecycle modeling, and finite hostile cases. They are not proof of live Desktop operation or service registration.",
  },
  {
    q: "Does it survive reboot or login?",
    a: "That is unverified. Historical sacrificial ServiceManagement evidence does not establish production migration, Login Items, FDA/TCC, reboot, or login behavior.",
  },
  {
    q: "Can suggestions move files?",
    a: "No. Suggestions are non-mutating and never authorize an automatic move, rename, delete, or upload.",
  },
  {
    q: "Was native accessibility verified?",
    a: "No. The local app was launched on a fixture, but direct menu pixels and accessibility-tree data were unavailable without a prohibited permission interaction. That lane is indeterminate.",
  },
];

export default function Faq() {
  return (
    <div className="mx-auto max-w-3xl">
      {QA.map(({ q, a }) => (
        <details key={q} className="group border-b py-1" style={{ borderColor: "var(--line)" }}>
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 rounded-lg px-2 py-4 text-left text-[15px] font-semibold [&::-webkit-details-marker]:hidden">
            {q}
            <span aria-hidden="true" className="shrink-0 text-lg transition-transform group-open:rotate-45" style={{ color: "var(--sky)" }}>+</span>
          </summary>
          <p className="px-2 pb-5 text-[15px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>{a}</p>
        </details>
      ))}
    </div>
  );
}
