import type { Metadata } from "next";
import Link from "next/link";
import Logo from "../components/Logo";

export const metadata: Metadata = {
  title: "Privacy — DeskTidy",
  description: "DeskTidy's privacy policy: the app makes no network connections, and this website sets no cookies and runs no trackers.",
  alternates: { canonical: "/privacy" },
};

export default function Privacy() {
  return (
    <main id="main" className="section-pad">
      <div className="container-site mx-auto max-w-2xl">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <Logo className="h-7 w-7" /> DeskTidy
        </Link>
        <h1 className="h-section mt-8">Privacy</h1>
        <p className="mt-2 text-sm" style={{ color: "var(--fg-faint)" }}>
          Last updated: August 13, 2026
        </p>

        <div className="mt-8 space-y-6 text-[15px] leading-relaxed" style={{ color: "var(--fg-soft)" }}>
          <section>
            <h2 className="text-lg font-bold" style={{ color: "var(--fg)" }}>The app</h2>
            <p className="mt-2">
              The DeskTidy application makes <strong>no network connections of any kind</strong>. It
              has no telemetry, no analytics, no crash reporting, no update checker, and no account
              system. Your files, file names, and the app&rsquo;s move log never leave your Mac. The
              optional Apple&nbsp;Intelligence feature runs entirely on-device and only writes
              suggestions to a local text file. You can verify all of this in the{" "}
              <a
                href="https://github.com/AnubisQuantumCipher/desktidy"
                target="_blank"
                rel="noopener noreferrer"
                style={{ color: "var(--sky)" }}
                className="font-semibold"
              >
                open source
              </a>
              .
            </p>
          </section>

          <section>
            <h2 className="text-lg font-bold" style={{ color: "var(--fg)" }}>This website</h2>
            <p className="mt-2">
              This website sets <strong>no cookies</strong> and runs <strong>no analytics or
              tracking scripts</strong>. Standard web-server request logs (IP address, user agent,
              requested page) may be processed transiently by our hosting provider (Vercel) to serve
              and secure the site.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-bold" style={{ color: "var(--fg)" }}>The early-access list</h2>
            <p className="mt-2">
              If you join the early-access list, we store exactly three things: your email address,
              the word &ldquo;website&rdquo; (so we know where the signup came from), and a
              timestamp. We use it for one purpose — telling you when the native DeskTidy app is
              available. No newsletter, no sharing, no selling. To be removed, email{" "}
              <a href="mailto:khephri.labs@proton.me" style={{ color: "var(--sky)" }} className="font-semibold">
                khephri.labs@proton.me
              </a>{" "}
              and we&rsquo;ll delete your address.
            </p>
          </section>

          <section>
            <h2 className="text-lg font-bold" style={{ color: "var(--fg)" }}>Questions</h2>
            <p className="mt-2">
              Email{" "}
              <a href="mailto:khephri.labs@proton.me" style={{ color: "var(--sky)" }} className="font-semibold">
                khephri.labs@proton.me
              </a>
              .
            </p>
          </section>
        </div>

        <p className="mt-10">
          <Link href="/" className="btn-secondary text-sm">
            ← Back to DeskTidy
          </Link>
        </p>
      </div>
    </main>
  );
}
