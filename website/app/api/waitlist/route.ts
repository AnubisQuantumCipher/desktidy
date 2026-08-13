import { neon } from "@neondatabase/serverless";
import { NextResponse } from "next/server";

export const runtime = "edge";

/* Early-access waitlist endpoint.
   - Provider-agnostic: any Postgres connection string via DATABASE_URL.
   - Unconfigured environments return 503 and the form tells the visitor
     honestly that signups aren't wired up (never silently discards).
   - Stores email + source + timestamp. Nothing else. No cookies set. */

const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;

export async function POST(request: Request) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    return NextResponse.json({ error: "waitlist_not_configured" }, { status: 503 });
  }

  let body: { email?: string; source?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const email = (body.email ?? "").trim().toLowerCase();
  const source = (body.source ?? "website").slice(0, 64);
  if (!EMAIL_RE.test(email) || email.length > 320) {
    return NextResponse.json({ error: "invalid_email" }, { status: 400 });
  }

  try {
    const sql = neon(url);
    const inserted = await sql`
      INSERT INTO waitlist (email, source)
      VALUES (${email}, ${source})
      ON CONFLICT (email) DO NOTHING
      RETURNING id
    `;
    if (inserted.length === 0) {
      return NextResponse.json({ status: "already_subscribed" }, { status: 409 });
    }
    return NextResponse.json({ status: "subscribed" }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "storage_error" }, { status: 500 });
  }
}
