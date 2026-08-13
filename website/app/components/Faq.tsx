/* Accessible FAQ built on native <details>/<summary> — keyboard + SR friendly
   with zero JS. Every answer mirrors the current implementation exactly. */

const QA: { q: string; a: React.ReactNode }[] = [
  {
    q: "Will it delete anything?",
    a: "No. DeskTidy has no delete path for your files — the only file operation it performs on your data is a move. Uninstalling removes DeskTidy itself, never your files.",
  },
  {
    q: "What happens when two files have the same name?",
    a: "Both are kept. The newcomer gets a “(dup 20260813-141212)” style suffix that preserves the extension. Nothing is ever overwritten — this is enforced by an automated test on every release.",
  },
  {
    q: "Does it upload my files anywhere?",
    a: "No. There isn't a single network call in the source code — no telemetry, no analytics, no update checks. The code is ~700 lines of Swift; you can verify this yourself on GitHub.",
  },
  {
    q: "Why does it need Full Disk Access?",
    a: "macOS protects your Desktop from background programs — a good thing. DeskTidy needs one-time permission for its small sorting binary (and only that binary) to organize the folder you chose. Without the grant it logs an error and touches nothing. The setup command walks you through it.",
  },
  {
    q: "Does it keep working after a restart?",
    a: "Yes. DeskTidy runs as standard launchd agents that start automatically at every login. Reboot, shut down, come back — it's running again by the time you see your Desktop.",
  },
  {
    q: "Does it require Apple Intelligence?",
    a: "No. The core sorter is deterministic and needs no AI at all. On macOS 26+ with Apple Intelligence, an optional pass suggests homes for unrecognized Inbox files — suggestions only, written to a file, entirely on-device. On older macOS this feature is compiled out.",
  },
  {
    q: "Can it organize Downloads instead of the Desktop?",
    a: (
      <>
        Yes — any folder: <code style={{ fontFamily: "var(--font-mono)" }}>desktidy setup --target ~/Downloads</code>.
      </>
    ),
  },
  {
    q: "Can I pause or undo it?",
    a: (
      <>
        Pause: <code style={{ fontFamily: "var(--font-mono)" }}>desktidy teardown</code> stops the service instantly;{" "}
        <code style={{ fontFamily: "var(--font-mono)" }}>desktidy setup</code> resumes it. There is no one-click undo
        button yet, but every move is logged with the exact final filename, so you can trace and reverse anything.
        An undo command is on the roadmap for the native app.
      </>
    ),
  },
  {
    q: "What happens to file types it doesn't recognize?",
    a: "They go to the Inbox folder — visibly set aside, never guessed at. Unknown means Inbox, not a wrong drawer.",
  },
  {
    q: "How do I uninstall it?",
    a: (
      <>
        <code style={{ fontFamily: "var(--font-mono)" }}>desktidy teardown && brew uninstall desktidy</code>. Your
        folders and every file DeskTidy ever sorted stay exactly where they are.
      </>
    ),
  },
  {
    q: "What versions of macOS are supported?",
    a: "macOS 14 Sonoma and later — that's what the continuous-integration suite verifies on every change. Earlier versions may build but are unverified. The optional AI triage additionally needs macOS 26+ with Apple Intelligence.",
  },
  {
    q: "Is it open source?",
    a: "Yes — MIT licensed, on GitHub. The sorter is ~700 lines of readable Swift with a public security policy and CI that tests the safety guarantees on every commit.",
  },
  {
    q: "Is there a native menu-bar app?",
    a: "Not yet — today DeskTidy is a command-line install with a background service. A native menu-bar app (pause/resume, activity feed, rules, undo) is planned; join early access above to hear when it ships.",
  },
];

export default function Faq() {
  return (
    <div className="mx-auto max-w-3xl">
      {QA.map(({ q, a }) => (
        <details
          key={q}
          className="group border-b py-1"
          style={{ borderColor: "var(--line)" }}
        >
          <summary className="flex cursor-pointer list-none items-center justify-between gap-4 rounded-lg px-2 py-4 text-left text-[15px] font-semibold [&::-webkit-details-marker]:hidden">
            {q}
            <span
              aria-hidden="true"
              className="shrink-0 text-lg transition-transform group-open:rotate-45"
              style={{ color: "var(--sky)" }}
            >
              +
            </span>
          </summary>
          <div className="px-2 pb-5 text-[15px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
            {a}
          </div>
        </details>
      ))}
    </div>
  );
}
