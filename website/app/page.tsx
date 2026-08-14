import BeforeAfter from "./components/BeforeAfter";
import CopyCommand from "./components/CopyCommand";
import Faq from "./components/Faq";
import HeroDemo from "./components/HeroDemo";
import Logo from "./components/Logo";
import Nav from "./components/Nav";
import WaitlistForm from "./components/WaitlistForm";

const GITHUB = "https://github.com/AnubisQuantumCipher/desktidy";

export default function Home() {
  return (
    <div id="top">
      <Nav />
      <main id="main">
        {/* ================= HERO ================= */}
        <section className="section-pad" id="product" aria-labelledby="hero-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <p className="eyebrow">For macOS 14 Sonoma and later · Free &amp; open source</p>
              <h1 id="hero-heading" className="h-display mt-4">
                Your Desktop. Always&nbsp;tidy.
              </h1>
              <p className="lede mx-auto mt-5 max-w-2xl">
                Drop anything on your Mac Desktop. DeskTidy waits until it&rsquo;s ready, files it in
                the right place, and tells you where it went.
              </p>
              <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
                <a href="#install" className="btn-primary">
                  Install with Homebrew
                </a>
                <a href="#demo" className="btn-secondary">
                  Watch it work
                </a>
              </div>
              <p className="mt-5 text-sm font-medium" style={{ color: "var(--fg-faint)" }}>
                Local by design &nbsp;·&nbsp; Never deletes &nbsp;·&nbsp; No account required
              </p>
            </div>

            <div className="mx-auto mt-14 max-w-4xl" id="demo">
              <HeroDemo />
            </div>
          </div>
        </section>

        {/* ================= THE PAIN ================= */}
        <section className="section-pad" style={{ background: "var(--bg-alt)" }} aria-labelledby="pain-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <h2 id="pain-heading" className="h-section">
                Your Desktop wasn&rsquo;t supposed to become a storage strategy.
              </h2>
              <p className="lede mt-5">
                It starts Monday with one screenshot. By Friday there are nine, plus{" "}
                <em>contract-FINAL-v3&nbsp;(2).pdf</em>, a screen recording you&rsquo;ll &ldquo;rename
                later,&rdquo; two zips, a stray Python script, and something called{" "}
                <em>untitled folder 2</em>. None of it is junk — that&rsquo;s why it&rsquo;s still
                there. It just never got put away.
              </p>
              <p className="lede mt-4">
                Every glance at the pile costs a little attention. DeskTidy exists to end that
                tax&nbsp;— not by deleting anything, but by quietly putting things where they go.
              </p>
            </div>
            <div className="mx-auto mt-12 max-w-4xl">
              <BeforeAfter />
            </div>
          </div>
        </section>

        {/* ================= HOW IT WORKS ================= */}
        <section className="section-pad" id="how-it-works" aria-labelledby="how-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <p className="eyebrow">How it works</p>
              <h2 id="how-heading" className="h-section mt-3">
                Drop it. Forget it. DeskTidy files it.
              </h2>
            </div>
            <div className="mx-auto mt-12 grid max-w-5xl gap-6 md:grid-cols-3">
              {[
                {
                  n: "1",
                  t: "Drop anything",
                  d: "Save, screenshot, download, drag — use your Mac exactly as you do now. DeskTidy watches the folder you chose (Desktop by default) in the background.",
                },
                {
                  n: "2",
                  t: "It waits, then files it",
                  d: "About twenty seconds after a file settles, deterministic rules move it to Documents, Screenshots, Videos, Audio, Archives, Code, or Folders. Unsure? It goes to Inbox — visibly set aside, never guessed.",
                },
                {
                  n: "3",
                  t: "You stay informed",
                  d: "A notification names the destination — click it and Finder opens with the file highlighted. Every move is written to a log you can read anytime.",
                },
              ].map((s) => (
                <div key={s.n} className="card-surface p-7">
                  <span
                    className="flex h-9 w-9 items-center justify-center rounded-full text-sm font-bold text-white"
                    style={{ background: "var(--sky)" }}
                    aria-hidden="true"
                  >
                    {s.n}
                  </span>
                  <h3 className="mt-4 text-lg font-bold">{s.t}</h3>
                  <p className="mt-2 text-[15px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                    {s.d}
                  </p>
                </div>
              ))}
            </div>
            <details className="card-surface mx-auto mt-8 max-w-3xl px-7 py-5">
              <summary className="cursor-pointer text-sm font-semibold" style={{ color: "var(--sky)" }}>
                The technical version, for the curious
              </summary>
              <div className="mt-3 space-y-2 text-sm leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                <p>
                  A launchd agent watches your target folder (WatchPaths, with a 60-second interval
                  backstop) and runs a small Swift binary. The binary skips anything modified in the
                  last 15 seconds and anything that looks like an in-progress download
                  (.crdownload, .part, .tmp…), classifies by extension and name, and moves with a
                  collision-safe rename so nothing is ever overwritten. A single-instance lock keeps
                  runs from colliding. A second agent tails the move log and posts the
                  notifications. It&rsquo;s ~700 lines of Swift you can read in one sitting.
                </p>
              </div>
            </details>
          </div>
        </section>

        {/* ================= SAFETY ================= */}
        <section className="section-pad" id="safety" style={{ background: "var(--bg-alt)" }} aria-labelledby="safety-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <p className="eyebrow">Safety is the product</p>
              <h2 id="safety-heading" className="h-section mt-3">
                It moves files. It never deletes them.
                <br />
                That&rsquo;s the whole trick.
              </h2>
              <p className="lede mt-5">
                Software that touches your files has to earn it. Every guarantee below is enforced in
                code, tested in CI on every change, and inspectable in the open source.
              </p>
            </div>
            <ul className="mx-auto mt-12 grid max-w-5xl gap-4 sm:grid-cols-2 lg:grid-cols-4">
              {[
                { t: "Never deletes", d: "There is no delete path for your files in the code. Moves only." },
                { t: "Never overwrites", d: "Name collision? Both files are kept — the newcomer gets a timestamp suffix." },
                { t: "Nothing leaves your Mac", d: "Zero network calls in the source. No telemetry, no analytics, no accounts." },
                { t: "Unknown means Inbox", d: "Unrecognized files are set aside visibly — never confidently misfiled." },
                { t: "Downloads are left alone", d: "A settle window plus .crdownload/.part/.tmp detection means no half-saved file is touched." },
                { t: "AI can't move files", d: "The optional on-device pass writes suggestions to a text file. It has no move, rename, or delete ability." },
                { t: "Every move is logged", d: "Timestamped, with the exact final filename — trace anything, anytime." },
                { t: "Uninstall keeps your files", d: "Teardown removes DeskTidy. Your organized folders stay exactly as they are." },
              ].map((c) => (
                <li key={c.t} className="card-surface p-5">
                  <p className="flex items-center gap-2 font-bold">
                    <span
                      aria-hidden="true"
                      className="flex h-5 w-5 items-center justify-center rounded-full text-[11px] text-white"
                      style={{ background: "var(--mint)" }}
                    >
                      ✓
                    </span>
                    {c.t}
                  </p>
                  <p className="mt-2 text-sm leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                    {c.d}
                  </p>
                </li>
              ))}
            </ul>

            <div className="card-surface mx-auto mt-10 max-w-3xl p-7">
              <h3 className="text-lg font-bold">About Full Disk Access — the honest version</h3>
              <p className="mt-3 text-[15px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                macOS protects your Desktop from background programs, which is exactly right. For
                DeskTidy to organize it, you grant one-time permission — to the small sorting binary
                only, not to a shell or a script something else could swap out. Until you grant it,
                DeskTidy logs an error and touches nothing. The <code style={{ fontFamily: "var(--font-mono)" }}>desktidy setup</code>{" "}
                command opens the right System Settings pane and walks you through it.{" "}
                <a
                  href={`${GITHUB}/blob/main/SECURITY.md`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-semibold"
                  style={{ color: "var(--sky)" }}
                >
                  Read the security policy →
                </a>
              </p>
            </div>
          </div>
        </section>

        {/* ================= LOCAL INTELLIGENCE ================= */}
        <section className="section-pad" aria-labelledby="ai-heading">
          <div className="container-site">
            <div className="mx-auto grid max-w-5xl items-center gap-10 md:grid-cols-2">
              <div>
                <p className="eyebrow">Optional · macOS 26+</p>
                <h2 id="ai-heading" className="h-section mt-3">
                  A second opinion for the Inbox — on your Mac, suggestions only.
                </h2>
                <p className="mt-5 text-[16px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                  When files DeskTidy can&rsquo;t classify pile up in Inbox, Apple&rsquo;s on-device
                  model can read each file&rsquo;s name and a short local preview, then write its
                  recommendation to a plain text file. That&rsquo;s the entire feature: it{" "}
                  <strong style={{ color: "var(--fg)" }}>cannot move, rename, delete, or upload anything</strong>{" "}
                  — the code gives it no such ability. File contents are treated as untrusted, so
                  instructions hidden inside a document are ignored. No Apple Intelligence? The
                  feature compiles out entirely and the sorter works exactly the same.
                </p>
              </div>
              <div className="card-surface p-6" role="img" aria-label="Example of the suggestions file: for the unknown file untitled-2.xyz, the on-device model suggests the Documents folder with medium certainty, because the preview mentions an invoice.">
                <p className="text-xs font-semibold" style={{ color: "var(--fg-faint)", fontFamily: "var(--font-mono)" }}>
                  Inbox/SMART_TRIAGE_SUGGESTIONS.md
                </p>
                <div className="mt-3 space-y-3 text-sm" aria-hidden="true">
                  <p style={{ color: "var(--fg-soft)" }}>
                    <strong style={{ color: "var(--fg)" }}>Suggestions only.</strong> The on-device
                    model did not move, rename, upload, or delete any file.
                  </p>
                  <div className="rounded-lg border p-3" style={{ borderColor: "var(--line)" }}>
                    <p style={{ fontFamily: "var(--font-mono)", fontSize: "12.5px" }}>
                      untitled-2.xyz → <span style={{ color: "var(--sky)" }}>Documents</span>{" "}
                      <span style={{ color: "var(--amber)" }}>(medium)</span>
                    </p>
                    <p className="mt-1 text-xs" style={{ color: "var(--fg-faint)" }}>
                      &ldquo;The preview mentions an invoice and a payment date.&rdquo;
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* ================= INSTALL ================= */}
        <section className="section-pad" id="install" style={{ background: "var(--bg-alt)" }} aria-labelledby="install-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <p className="eyebrow">Install</p>
              <h2 id="install-heading" className="h-section mt-3">
                Two commands. Under a minute.
              </h2>
              <p className="lede mt-4">
                DeskTidy installs with <a href="https://brew.sh" target="_blank" rel="noopener noreferrer" className="font-semibold" style={{ color: "var(--sky)" }}>Homebrew</a>, builds
                from source on your own Mac, and refuses to install itself if its safety self-test
                fails.
              </p>
            </div>
            <div className="mx-auto mt-10 max-w-2xl space-y-3">
              <CopyCommand command="brew install anubisquantumcipher/tap/desktidy" label="install" />
              <CopyCommand command="desktidy setup" label="setup" />
            </div>
            <div className="mx-auto mt-6 max-w-2xl text-center text-sm leading-relaxed" style={{ color: "var(--fg-soft)" }}>
              <p>
                <code style={{ fontFamily: "var(--font-mono)" }}>setup</code> starts the background service and walks you through the one-time Full Disk
                Access grant. Prefer a different folder?{" "}
                <code style={{ fontFamily: "var(--font-mono)" }}>desktidy setup --target ~/Downloads</code>
              </p>
            </div>
            <details className="card-surface mx-auto mt-8 max-w-2xl px-7 py-5">
              <summary className="cursor-pointer text-sm font-semibold" style={{ color: "var(--sky)" }}>
                Day-to-day commands
              </summary>
              <div className="mt-4 space-y-2.5">
                <CopyCommand command="desktidy status" label="status" />
                <CopyCommand command="desktidy sort-now" label="sort now" />
                <CopyCommand command="desktidy log" label="log" />
                <CopyCommand command="desktidy teardown" label="teardown" />
              </div>
              <p className="mt-4 text-xs" style={{ color: "var(--fg-faint)" }}>
                No Homebrew? Install it first from brew.sh, or clone the repo and run ./install.sh.
                Optional: <code style={{ fontFamily: "var(--font-mono)" }}>brew install terminal-notifier</code> makes
                the notifications clickable.
              </p>
            </details>
          </div>
        </section>

        {/* ================= USE CASES ================= */}
        <section className="section-pad" aria-labelledby="uses-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <h2 id="uses-heading" className="h-section">
                Built for the way Desktops actually get messy
              </h2>
            </div>
            <div className="mx-auto mt-12 grid max-w-5xl gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {[
                { t: "Screenshot-heavy work", d: "Support, QA, design reviews — every ⌘⇧4 lands in Screenshots, not on top of yesterday's forty." },
                { t: "Designers & video creators", d: "Exports, recordings, and asset zips file themselves into Videos, Images, and Archives while you keep working." },
                { t: "Developers", d: "Stray scripts, JSON dumps, and config files head to Code. Your Desktop stops being a scratch buffer." },
                { t: "Students & researchers", d: "Lecture PDFs, papers, and notes collect in Documents instead of scattering across the semester." },
                { t: "The 'temporary' Desktop", d: "If your Desktop is a landing zone on purpose, DeskTidy makes it one that empties itself." },
                { t: "Downloads folder duty", d: "Point it at ~/Downloads instead — the same rules tame the other folder that fills itself." },
              ].map((u) => (
                <div key={u.t} className="card-surface p-6">
                  <h3 className="font-bold">{u.t}</h3>
                  <p className="mt-2 text-sm leading-relaxed" style={{ color: "var(--fg-soft)" }}>
                    {u.d}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ================= COMPARISON ================= */}
        <section className="section-pad" style={{ background: "var(--bg-alt)" }} aria-labelledby="compare-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <h2 id="compare-heading" className="h-section">
                Not a &ldquo;Mac cleaner.&rdquo; The opposite, actually.
              </h2>
              <p className="lede mt-4">
                Cleaner apps hunt for things to delete. Rules engines make you build the system.
                DeskTidy is the third option: a clean desktop without writing a single rule — and
                without deleting a single file.
              </p>
            </div>
            <div className="card-surface mx-auto mt-10 max-w-3xl overflow-x-auto">
              <table className="w-full min-w-[560px] border-collapse text-[15px]">
                <caption className="sr-only">
                  How DeskTidy differs from traditional Mac cleaner applications
                </caption>
                <thead>
                  <tr className="border-b text-left" style={{ borderColor: "var(--line)" }}>
                    <th scope="col" className="p-5 font-bold">DeskTidy</th>
                    <th scope="col" className="p-5 font-bold" style={{ color: "var(--fg-soft)" }}>
                      Traditional Mac cleaner
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[
                    ["Organizes the folder you choose", "Searches your disk for things to delete"],
                    ["Unknown files go to a visible Inbox", "Broad “junk” recommendations to approve"],
                    ["Runs entirely on your Mac, no account", "Often wants accounts, cloud, subscriptions"],
                    ["One small focused utility (~700 lines)", "A suite of loosely related tools"],
                    ["A readable log of every single move", "An opaque “space saved” score"],
                  ].map(([a, b]) => (
                    <tr key={a} className="border-b last:border-0" style={{ borderColor: "var(--line)" }}>
                      <td className="p-5">
                        <span className="mr-2" style={{ color: "var(--mint)" }} aria-hidden="true">✓</span>
                        {a}
                      </td>
                      <td className="p-5" style={{ color: "var(--fg-soft)" }}>{b}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {/* ================= OPEN SOURCE + EARLY ACCESS ================= */}
        <section className="section-pad" id="early-access" aria-labelledby="oss-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <p className="eyebrow">Open source today · Native app next</p>
              <h2 id="oss-heading" className="h-section mt-3">
                Free forever at its core.
              </h2>
              <p className="lede mt-5">
                DeskTidy is MIT-licensed and public on GitHub — every guarantee on this page is a
                claim you can check against the source. The command-line version you can
                install today stays free. The Homebrew formula remains v1.1.2 and does not
                include the experimental R1A/R1B app work.
              </p>
              <p className="lede mt-4">
                A read-only experimental menu-bar status surface exists in source only — not
                packaged, not in Homebrew. Next up for a real app release: pause and resume,
                a live activity feed, one-click undo, and visual rules — as a one-time-purchase,
                no-subscription product. Undo is planned, not shipped. Want in when it&rsquo;s ready?
              </p>
              <div className="mt-8">
                <WaitlistForm />
              </div>
              <p className="mt-6">
                <a
                  href={GITHUB}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-secondary text-sm"
                >
                  <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true">
                    <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" />
                  </svg>
                  Inspect the source on GitHub
                </a>
              </p>
            </div>
          </div>
        </section>

        {/* ================= FAQ ================= */}
        <section className="section-pad" id="faq" style={{ background: "var(--bg-alt)" }} aria-labelledby="faq-heading">
          <div className="container-site">
            <div className="mx-auto max-w-3xl text-center">
              <h2 id="faq-heading" className="h-section">
                The questions you should ask
              </h2>
              <p className="lede mt-4">
                Straight answers, matching exactly what the code does today.
              </p>
            </div>
            <div className="mt-10">
              <Faq />
            </div>
          </div>
        </section>

        {/* ================= FINAL CTA ================= */}
        <section className="section-pad" aria-labelledby="cta-heading">
          <div className="container-site">
            <div
              className="card-surface mx-auto max-w-4xl px-8 py-14 text-center"
              style={{
                background:
                  "linear-gradient(180deg, var(--card) 0%, color-mix(in srgb, var(--sky-wash) 55%, var(--card)) 100%)",
              }}
            >
              <div className="mx-auto mb-6 flex justify-center" aria-hidden="true">
                <Logo className="h-14 w-14" />
              </div>
              <h2 id="cta-heading" className="h-section">
                A clean Desktop, without another chore.
              </h2>
              <p className="lede mx-auto mt-4 max-w-xl">
                Install DeskTidy, drop a file, and watch your Mac put it away.
              </p>
              <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
                <a href="#install" className="btn-primary">
                  Install with Homebrew
                </a>
                <a
                  href={GITHUB}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-secondary"
                >
                  View on GitHub
                </a>
              </div>
              <p className="mt-5 text-sm" style={{ color: "var(--fg-faint)" }}>
                Free · Open source · Uninstalls cleanly, your files stay put
              </p>
            </div>
          </div>
        </section>
      </main>

      {/* ================= FOOTER ================= */}
      <footer className="border-t py-12" style={{ borderColor: "var(--line)" }}>
        <div className="container-site">
          <div className="flex flex-col items-start justify-between gap-8 md:flex-row">
            <div>
              <p className="flex items-center gap-2 font-semibold">
                <Logo className="h-6 w-6" /> DeskTidy
              </p>
              <p className="mt-2 max-w-xs text-sm" style={{ color: "var(--fg-faint)" }}>
                Your Mac Desktop, organized automatically. Local, safe, open source.
              </p>
            </div>
            <nav aria-label="Footer" className="grid grid-cols-2 gap-x-12 gap-y-2 text-sm sm:grid-cols-3">
              {[
                { href: GITHUB, label: "GitHub" },
                { href: `${GITHUB}/releases`, label: "Releases" },
                { href: `${GITHUB}#readme`, label: "Documentation" },
                { href: `${GITHUB}/blob/main/SECURITY.md`, label: "Security policy" },
                { href: `${GITHUB}/blob/main/LICENSE`, label: "License (MIT)" },
                { href: `${GITHUB}/blob/main/CHANGELOG.md`, label: "Changelog" },
                { href: "/privacy", label: "Privacy" },
                { href: "mailto:khephri.labs@proton.me", label: "Contact" },
              ].map((l) => (
                <a
                  key={l.label}
                  href={l.href}
                  className="py-1"
                  style={{ color: "var(--fg-soft)" }}
                  {...(l.href.startsWith("http") ? { target: "_blank", rel: "noopener noreferrer" } : {})}
                >
                  {l.label}
                </a>
              ))}
            </nav>
          </div>
          <p className="mt-10 text-xs" style={{ color: "var(--fg-faint)" }}>
            © {new Date().getFullYear()} DeskTidy · MIT licensed · This site sets no cookies and runs
            no trackers.
          </p>
        </div>
      </footer>
    </div>
  );
}
