const GITHUB = "https://github.com/AnubisQuantumCipher/desktidy";

export default function Home() {
  return (
    <main className="mx-auto flex min-h-screen max-w-3xl items-center px-6 py-20">
      <section aria-labelledby="status-heading" className="card-surface w-full p-8 sm:p-12">
        <p className="eyebrow">DeskTidy · repository status</p>
        <h1 id="status-heading" className="h-display mt-4">
          Local deployment is operational. Public distribution is not ready.
        </h1>
        <div className="mt-8 space-y-5 text-[16px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
          <p>
            DeskTidy has an ad-hoc Apple Silicon macOS 14+ local deployment on the operator
            Mac. Its single-authority, movement, receipt, Undo, migration, and rollback claims
            are backed by repository evidence. It is not Developer ID signed, notarized,
            Gatekeeper-accepted public distribution, or a public native installer.
          </p>
          <p>
            This source update is not a website deployment. A previously deployed site may not
            describe the current repository state; use the repository evidence instead.
          </p>
          <p>
            Fixture gates cover guarded movement, receipts, notifications, Undo, history,
            bounded App Intents, lifecycle modeling, and finite hostile cases. A separately
            recorded live migration and named-canary cycle establish this Mac&rsquo;s current local
            operation; they do not establish Login Items behavior, reboot/login survival,
            complete keyboard/VoiceOver acceptance, or public-distribution safety.
          </p>
          <p>
            The package&rsquo;s receipt chain is unkeyed integrity evidence, not authentication.
            No no-network binary audit has been completed for this local RC.
          </p>
        </div>
        <a
          href={GITHUB}
          className="btn-primary mt-8 inline-flex"
          target="_blank"
          rel="noopener noreferrer"
        >
          Inspect repository evidence
        </a>
      </section>
    </main>
  );
}
