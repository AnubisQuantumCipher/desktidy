"use client";

import { useState } from "react";

type State = "idle" | "sending" | "done" | "already" | "error" | "unconfigured";

export default function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<State>("idle");

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (state === "sending") return;
    setState("sending");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, source: "website" }),
      });
      if (res.status === 503) return setState("unconfigured");
      if (res.status === 409) return setState("already");
      if (!res.ok) return setState("error");
      setState("done");
      setEmail("");
    } catch {
      setState("error");
    }
  };

  return (
    <form onSubmit={submit} className="mx-auto flex w-full max-w-md flex-col gap-3" noValidate={false}>
      <div className="flex flex-col gap-2 sm:flex-row">
        <label className="sr-only" htmlFor="waitlist-email">
          Email address for early access
        </label>
        <input
          id="waitlist-email"
          type="email"
          required
          autoComplete="email"
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="min-w-0 flex-1 rounded-full border px-5 py-3 text-sm"
          style={{ background: "var(--card)", borderColor: "var(--line)", color: "var(--fg)" }}
        />
        <button type="submit" className="btn-primary justify-center text-sm" disabled={state === "sending"}>
          {state === "sending" ? "Joining…" : "Join early access"}
        </button>
      </div>
      <p aria-live="polite" className="min-h-5 text-center text-sm" style={{ color: state === "error" ? "var(--amber)" : "var(--fg-faint)" }}>
        {state === "done" && "✓ You're on the list. We'll email you when the app is ready — nothing else."}
        {state === "already" && "You're already on the list — nothing more to do."}
        {state === "error" && "Something went wrong. Please try again, or email khephri.labs@proton.me."}
        {state === "unconfigured" &&
          "Signups aren't wired up in this environment. Email khephri.labs@proton.me and we'll add you by hand."}
        {(state === "idle" || state === "sending") && "One email when it ships. No newsletter, no spam, delete-on-request."}
      </p>
    </form>
  );
}
