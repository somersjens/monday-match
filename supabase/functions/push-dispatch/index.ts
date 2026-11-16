import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { classify, compose, constantTimeEqual, type Entry } from "./policy.ts";

// Sends the pushes the database queued in notification_private.outbox.
// Called every 15 seconds by pg_cron (see docs/notifications.md), never by
// the app. Secrets: APNS_KEY_ID, APNS_PRIVATE_KEY (.p8 contents),
// APPLE_TEAM_ID and PUSH_DISPATCH_SECRET. No tokens, names or keys are logged.

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

// APNs wants a provider token refreshed between 20 and 60 minutes.
let cachedToken: { value: string; issuedAt: number } | null = null;
async function providerToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && now - cachedToken.issuedAt < 40 * 60_000) return cachedToken.value;
  const keyID = Deno.env.get("APNS_KEY_ID")!, teamID = Deno.env.get("APPLE_TEAM_ID")!;
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/\\n/g, "\n");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID).setIssuedAt(Math.floor(now / 1000))
    .sign(await importPKCS8(privateKey, "ES256"));
  cachedToken = { value, issuedAt: now };
  return value;
}

async function send(entry: Entry) {
  const { headers, body } = compose(entry);
  const host = entry.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  try {
    const result = await fetch(`https://${host}/3/device/${entry.token}`, {
      method: "POST",
      headers: { ...headers, authorization: `bearer ${await providerToken()}`, "content-type": "application/json" },
      body,
    });
    const reason = result.status === 200 ? undefined : (await result.json().catch(() => ({})))?.reason;
    if (reason === "ExpiredProviderToken") cachedToken = null;
    return { outcome: classify(result.status, reason), detail: reason ?? String(result.status) };
  } catch {
    return { outcome: "retry" as const, detail: "network" };
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const secret = Deno.env.get("PUSH_DISPATCH_SECRET");
  if (!secret || !constantTimeEqual(request.headers.get("X-Dispatch-Secret") ?? "", secret)) {
    return response(401, { error: "Not allowed" });
  }
  if (!Deno.env.get("APNS_KEY_ID") || !Deno.env.get("APNS_PRIVATE_KEY") || !Deno.env.get("APPLE_TEAM_ID")) {
    return response(503, { error: "APNs is not configured yet" });
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });

  const { data, error } = await admin.rpc("push_claim_due", { p_limit: 100 });
  if (error) return response(500, { error: "Claim failed" });
  const entries = (data ?? []) as Entry[];

  // One outbox row can go to several phones; it is done when any succeeds.
  const results = new Map<number, { sent: boolean; retry: boolean; detail: string }>();
  await Promise.all(entries.map(async (entry) => {
    const { outcome, detail } = await send(entry);
    if (outcome === "revoke") await admin.rpc("push_revoke_token", { p_token: entry.token });
    const current = results.get(entry.outbox_id) ?? { sent: false, retry: false, detail };
    results.set(entry.outbox_id, {
      sent: current.sent || outcome === "sent",
      retry: current.retry || outcome === "retry",
      detail: outcome === "sent" ? (entry.visible ? "sent" : "background") : current.detail,
    });
  }));

  for (const [id, result] of results) {
    await admin.rpc("push_complete", {
      p_outbox_id: id,
      p_outcome: result.sent ? result.detail : result.detail,
      p_retry: !result.sent && result.retry,
    });
  }
  return response(200, { claimed: entries.length, rows: results.size });
});
