import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";
import { classify, classifyFCM, compose, composeFCM, constantTimeEqual, type Entry, type Outcome, platformOf }
  from "./policy.ts";

// Sends the pushes the database queued in notification_private.outbox.
// Called every 15 seconds by pg_cron (see docs/notifications.md), never by
// the app. No tokens, names or keys are logged.
//
// Secrets:
// - PUSH_DISPATCH_SECRET: the shared secret pg_cron sends.
// - iOS (APNs): APNS_KEY_ID, APNS_PRIVATE_KEY (.p8 contents), APPLE_TEAM_ID.
// - Android (FCM): FCM_SERVICE_ACCOUNT, the JSON key of a Firebase service
//   account with the "Firebase Cloud Messaging API Admin" role. Optional
//   until there is an Android app; Android rows fail as "fcm_not_configured".

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

const apnsReady = () =>
  Boolean(Deno.env.get("APNS_KEY_ID") && Deno.env.get("APNS_PRIVATE_KEY") && Deno.env.get("APPLE_TEAM_ID"));

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
function serviceAccount(): ServiceAccount | null {
  try {
    const parsed = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
    return parsed?.project_id && parsed?.client_email && parsed?.private_key ? parsed : null;
  } catch {
    return null;
  }
}

// ===== APNs ==================================================================

// APNs wants a provider token refreshed between 20 and 60 minutes.
let cachedAPNsToken: { value: string; issuedAt: number } | null = null;
async function apnsToken(): Promise<string> {
  const now = Date.now();
  if (cachedAPNsToken && now - cachedAPNsToken.issuedAt < 40 * 60_000) return cachedAPNsToken.value;
  const keyID = Deno.env.get("APNS_KEY_ID")!, teamID = Deno.env.get("APPLE_TEAM_ID")!;
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/\\n/g, "\n");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID).setIssuedAt(Math.floor(now / 1000))
    .sign(await importPKCS8(privateKey, "ES256"));
  cachedAPNsToken = { value, issuedAt: now };
  return value;
}

async function sendAPNs(entry: Entry): Promise<{ outcome: Outcome; detail: string }> {
  const { headers, body } = compose(entry);
  const host = entry.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  try {
    const result = await fetch(`https://${host}/3/device/${entry.token}`, {
      method: "POST",
      headers: { ...headers, authorization: `bearer ${await apnsToken()}`, "content-type": "application/json" },
      body,
    });
    const reason = result.status === 200 ? undefined : (await result.json().catch(() => ({})))?.reason;
    if (reason === "ExpiredProviderToken") cachedAPNsToken = null;
    return { outcome: classify(result.status, reason), detail: reason ?? String(result.status) };
  } catch {
    return { outcome: "retry", detail: "network" };
  }
}

// ===== FCM ===================================================================

// A Google OAuth access token lasts an hour; refresh after 50 minutes.
let cachedFCMToken: { value: string; issuedAt: number } | null = null;
async function fcmToken(account: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (cachedFCMToken && now - cachedFCMToken.issuedAt < 50 * 60_000) return cachedFCMToken.value;
  const seconds = Math.floor(now / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email).setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(seconds).setExpirationTime(seconds + 3600)
    .sign(await importPKCS8(account.private_key.replace(/\\n/g, "\n"), "RS256"));
  const result = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!result.ok) throw new Error("FCM authorization failed");
  const value = (await result.json()).access_token as string;
  cachedFCMToken = { value, issuedAt: now };
  return value;
}

async function sendFCM(entry: Entry, account: ServiceAccount): Promise<{ outcome: Outcome; detail: string }> {
  try {
    const result = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${await fcmToken(account)}`, "content-type": "application/json" },
      body: JSON.stringify(composeFCM(entry)),
    });
    let code: string | undefined;
    if (result.status !== 200) {
      const error = (await result.json().catch(() => ({})))?.error;
      code = (error?.details ?? []).find((item: { errorCode?: string }) => item?.errorCode)?.errorCode ?? error?.status;
    } else {
      await result.body?.cancel();
    }
    if (result.status === 401) cachedFCMToken = null;
    return { outcome: classifyFCM(result.status, code), detail: code ?? String(result.status) };
  } catch {
    return { outcome: "retry", detail: "network" };
  }
}

// ===== Dispatch ==============================================================

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const secret = Deno.env.get("PUSH_DISPATCH_SECRET");
  if (!secret || !constantTimeEqual(request.headers.get("X-Dispatch-Secret") ?? "", secret)) {
    return response(401, { error: "Not allowed" });
  }
  const account = serviceAccount();
  if (!apnsReady() && !account) return response(503, { error: "No push service is configured yet" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });

  const { data, error } = await admin.rpc("push_claim_due", { p_limit: 100 });
  if (error) return response(500, { error: "Claim failed" });
  const entries = (data ?? []) as Entry[];

  const send = (entry: Entry) => {
    if (platformOf(entry) === "android") {
      return account ? sendFCM(entry, account)
        : Promise.resolve({ outcome: "failed" as const, detail: "fcm_not_configured" });
    }
    return apnsReady() ? sendAPNs(entry)
      : Promise.resolve({ outcome: "failed" as const, detail: "apns_not_configured" });
  };

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
    await admin.rpc("push_complete", { p_outbox_id: id, p_outcome: result.detail, p_retry: !result.sent && result.retry });
  }
  return response(200, { claimed: entries.length, rows: results.size });
});
