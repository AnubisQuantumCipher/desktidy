const GITHUB = "https://github.com/AnubisQuantumCipher/desktidy";

export default function Home() {
  return (
    <main className="mx-auto flex min-h-screen max-w-3xl items-center px-6 py-20">
      <section aria-labelledby="status-heading" className="card-surface w-full p-8 sm:p-12">
        <p className="eyebrow">DeskTidy · repository status</p>
        <h1 id="status-heading" className="h-display mt-4">
          Local release-candidate work. Not a public installer.
        </h1>
        <div className="mt-8 space-y-5 text-[16px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
          <p>
            DeskTidy has an ad-hoc Apple Silicon macOS 14+ local release candidate that was
            built and checked only on isolated fixture paths. It is not Developer ID signed,
            notarized, publicly released, or a Homebrew distribution.
          </p>
          <p>
            This source update is not a website deployment. A previously deployed site may not
            describe the current repository state; use the repository evidence instead.
          </p>
          <p>
            Local fixture gates cover guarded movement, receipts, notifications, Undo, history,
            bounded App Intents, lifecycle modeling, and finite hostile cases. They do not prove
            live Desktop operation, live service registration, Login Items/FDA/TCC behavior,
            reboot/login survival, or native menu accessibility. Suggestions remain non-mutating.
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
