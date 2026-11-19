import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { bundleID, Rejected, verifyAppleJWS, verifyAppleRenewal, verifyAppleTransaction } from "./verify.ts";

// Records access (lifetime, early adopter, the monthly plan) against the
// signed-in account, after checking the store's own signature, so another
// device (or the Android app) can rely on it. The app sends StoreKit 2 signed
// transactions; Google Play purchases will arrive here too once there is a
// Play account (store "play").
//
// The same URL is the App Store Server Notifications V2 endpoint: Apple posts
// `{ signedPayload }` without a user when a plan renews, lapses or is
// refunded, and the purchase's row is brought up to date. Such a
// notification can only change a purchase an account already recorded.
// "Verify JWT with legacy secret" must be off: the user, or Apple's
// signature, is checked here. Nothing about the purchase is logged.

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

// Apple's notification: verified, then applied to an existing row only.
// Apple retries anything but a 200, so only an unverifiable payload or a
// database error asks for that.
async function handleNotification(admin: ReturnType<typeof createClient>, signedPayload: unknown) {
  let notification: Record<string, unknown>;
  try { notification = await verifyAppleJWS(signedPayload as string); }
  catch { return response(400, { error: "Not an App Store notification" }); }
  const data = notification.data as Record<string, unknown> | undefined;
  // A TEST notification, or one about another app: nothing to record.
  if (!data || data.bundleId !== bundleID || typeof data.signedTransactionInfo !== "string") {
    return response(200, { status: "ignored" });
  }
  let verified;
  try { verified = await verifyAppleTransaction(data.signedTransactionInfo); }
  catch { return response(200, { status: "ignored" }); }
  const { data: status, error } = await admin.rpc("update_store_entitlement", {
    p_store: "app_store", p_original_transaction_id: verified.originalTransactionID,
    p_expires_at: verified.expiresAt?.toISOString() ?? null, p_revoked_at: verified.revokedAt?.toISOString() ?? null,
  });
  if (error) return response(500, { error: "Not saved" });
  // Turning auto-renew off (or on again) arrives as its own notification.
  if (typeof data.signedRenewalInfo === "string") {
    try {
      const renewal = await verifyAppleRenewal(data.signedRenewalInfo);
      const { error: renewalError } = await admin.rpc("set_store_auto_renew", {
        p_user_id: null, p_store: "app_store", p_original_transaction_id: renewal.originalTransactionID,
        p_auto_renews: renewal.autoRenews,
      });
      if (renewalError) return response(500, { error: "Not saved" });
    } catch { /* No usable renewal info: the transaction part is saved. */ }
  }
  return response(200, { status });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });
  const raw = await request.text();
  if (raw.length > 100_000) return response(413, { error: "Request too large" });
  let body: Record<string, unknown> | null;
  try { body = JSON.parse(raw); } catch { body = null; }
  if (typeof body?.signedPayload === "string") return handleNotification(admin, body.signedPayload);

  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return response(401, { error: "Authentication required" });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return response(401, { error: "Authentication required" });

  const transactions = body?.appStoreTransactions;
  const renewals = body?.appStoreRenewals ?? [];
  if (!Array.isArray(transactions) || transactions.length === 0 || transactions.length > 10) {
    return response(400, { error: "Between 1 and 10 signed transactions required" });
  }
  if (!Array.isArray(renewals) || renewals.length > 10) {
    return response(400, { error: "At most 10 signed renewals" });
  }

  const results = [];
  for (const jws of transactions) {
    try {
      const verified = await verifyAppleTransaction(jws as string);
      const { data, error } = await admin.rpc("record_store_entitlement", {
        p_user_id: auth.user.id, p_store: "app_store", p_product_id: verified.productID,
        p_original_transaction_id: verified.originalTransactionID,
        p_purchased_at: verified.purchasedAt.toISOString(),
        p_revoked_at: verified.revokedAt?.toISOString() ?? null, p_environment: verified.environment,
        p_expires_at: verified.expiresAt?.toISOString() ?? null,
      });
      results.push({ product_id: verified.productID, status: error ? "error" : data });
    } catch (error) {
      results.push({ status: error instanceof Rejected ? "rejected" : "error" });
    }
  }
  // Whether each monthly plan will renew, after its purchase is recorded.
  const renewalResults = [];
  for (const jws of renewals) {
    try {
      const renewal = await verifyAppleRenewal(jws as string);
      const { data, error } = await admin.rpc("set_store_auto_renew", {
        p_user_id: auth.user.id, p_store: "app_store", p_original_transaction_id: renewal.originalTransactionID,
        p_auto_renews: renewal.autoRenews,
      });
      renewalResults.push({ status: error ? "error" : data });
    } catch (error) {
      renewalResults.push({ status: error instanceof Rejected ? "rejected" : "error" });
    }
  }
  return response(200, { results, renewals: renewalResults });
});
