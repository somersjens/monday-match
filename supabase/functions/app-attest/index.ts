import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { appleRoot, fromBase64, Rejected, verifyAssertion, verifyAttestation } from "./verify.ts";

// Proves that a photo scan comes from the genuine app on a genuine iPhone
// (Apple App Attest), then records it with attested = true. Actions:
//   challenge  → { id, challenge }                      one-time, 5 minutes
//   register   { challengeId, keyId, attestation }      Apple-certified key
//   photo      { challengeId, keyId, assertion, clientData, photoId }
// clientData is the JSON the phone signed: {"challenge","photo_id","purpose"}.
// "Verify JWT with legacy secret" must be off: the user is checked here.
// Nothing about keys or photos is logged; a refusal or failure logs its
// action and reason only, so it can be traced.

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const reason = (error: unknown) => error instanceof Error ? error.name + ": " + error.message : String(error);
const isText = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= max;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return response(401, { error: "Authentication required" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return response(401, { error: "Authentication required" });
  const user = auth.user.id;

  const raw = await request.text();
  if (raw.length > 20_000) return response(413, { error: "Request too large" });
  let body: Record<string, unknown>;
  try { body = JSON.parse(raw) ?? {}; } catch { return response(400, { error: "JSON required" }); }

  const takeChallenge = async () => {
    if (!isText(body.challengeId, 36) || !uuid.test(body.challengeId)) throw new Rejected("Challenge required");
    const { data } = await admin.rpc("app_attest_take_challenge", { p_user_id: user, p_id: body.challengeId });
    if (typeof data !== "string" || !data) throw new Rejected("Challenge expired");
    return fromBase64(data);
  };

  try {
    switch (body.action) {
      case "challenge": {
        const { data, error } = await admin.rpc("app_attest_issue_challenge", { p_user_id: user });
        if (error) return response(429, { error: "Too many challenges" });
        return response(200, data);
      }
      case "register": {
        if (!isText(body.keyId, 64) || !isText(body.attestation, 16_000)) throw new Rejected("Attestation required");
        const challenge = await takeChallenge();
        const attested = await verifyAttestation({ attestation: fromBase64(body.attestation), challenge,
          keyID: body.keyId, root: await appleRoot() });
        const { error } = await admin.rpc("app_attest_register_key", { p_user_id: user, p_key_id: body.keyId,
          p_public_key: attested.publicKey, p_environment: attested.environment });
        if (error) {
          console.error(JSON.stringify({ action: "register", failed: "store", reason: error.message }));
          return response(500, { error: "Key not stored" });
        }
        return response(200, { registered: true });
      }
      case "photo": {
        if (!isText(body.keyId, 64) || !isText(body.assertion, 4_000) || !isText(body.clientData, 1_000) ||
            !isText(body.photoId, 36) || !uuid.test(body.photoId)) throw new Rejected("Assertion required");
        const challenge = await takeChallenge();
        const clientData = fromBase64(body.clientData);
        const signed = JSON.parse(new TextDecoder().decode(clientData));
        if (signed?.purpose !== "photo_verification" || signed?.photo_id?.toLowerCase() !== body.photoId.toLowerCase() ||
            signed?.challenge !== btoa(String.fromCharCode(...challenge))) throw new Rejected("Client data mismatch");
        const { data: key } = await admin.rpc("app_attest_key", { p_user_id: user, p_key_id: body.keyId });
        if (!key) return response(409, { error: "unknown_key" });
        const counter = await verifyAssertion({ assertion: fromBase64(body.assertion), clientData,
          publicKey: key.public_key, signCount: Number(key.sign_count) });
        const { data: used } = await admin.rpc("app_attest_use_key", { p_user_id: user, p_key_id: body.keyId,
          p_counter: counter });
        if (!used) throw new Rejected("Replayed assertion");
        const { data: recorded, error } = await admin.rpc("record_attested_photo_verification",
          { p_user_id: user, p_photo_id: body.photoId });
        if (error?.message?.includes("Daily verification limit")) return response(429, { error: "daily_limit" });
        if (error) return response(409, { error: "not_recorded" });
        return response(200, { recorded: recorded === true });
      }
      default:
        return response(400, { error: "Unknown action" });
    }
  } catch (error) {
    console.error(JSON.stringify({ action: body.action, rejected: error instanceof Rejected, reason: reason(error) }));
    if (error instanceof Rejected) return response(403, { error: "rejected" });
    return response(500, { error: "Attestation failed" });
  }
});
