import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

// Revokes the Sign in with Apple tokens of an account that is being deleted,
// as App Store Review Guideline 5.1.1(v) requires. The app asks Apple for a
// fresh authorization code first; it is exchanged here and revoked at once.
// Secrets: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (the .p8 contents)
// and optionally APPLE_CLIENT_ID (defaults to the app's bundle identifier).
// No codes, tokens or keys are logged.

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

const form = (values: Record<string, string>) => ({
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams(values),
});

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return response(401, { error: "Authentication required" });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return response(401, { error: "Authentication required" });
  const identity = auth.user.identities?.find((item) => item.provider === "apple");
  if (!identity) return response(400, { error: "This account doesn't use Sign in with Apple" });

  const teamID = Deno.env.get("APPLE_TEAM_ID"), keyID = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const clientID = Deno.env.get("APPLE_CLIENT_ID") ?? "Hakketjak.monday-match";
  if (!teamID || !keyID || !privateKey) return response(503, { error: "Apple revocation is not configured yet" });

  try {
    const raw = await request.text();
    if (raw.length > 4096) return response(413, { error: "Request too large" });
    const code = JSON.parse(raw)?.authorizationCode;
    if (typeof code !== "string" || code.length === 0 || code.length > 2048) {
      return response(400, { error: "Authorization code required" });
    }

    const clientSecret = await new SignJWT({})
      .setProtectedHeader({ alg: "ES256", kid: keyID })
      .setIssuer(teamID).setSubject(clientID).setAudience("https://appleid.apple.com")
      .setIssuedAt().setExpirationTime("5m")
      .sign(await importPKCS8(privateKey, "ES256"));

    const exchange = await fetch("https://appleid.apple.com/auth/token", form({
      client_id: clientID, client_secret: clientSecret, code, grant_type: "authorization_code",
    }));
    if (!exchange.ok) return response(400, { error: "Apple didn't accept the authorization" });
    const tokens = await exchange.json();

    // Only the Apple ID linked to this account may be revoked through it.
    const appleSubject = JSON.parse(atob(tokens.id_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).sub;
    const linkedSubject = identity.identity_data?.sub ?? identity.id;
    if (appleSubject !== linkedSubject) return response(403, { error: "A different Apple ID was used" });

    const revoked = await fetch("https://appleid.apple.com/auth/revoke", form({
      client_id: clientID, client_secret: clientSecret,
      token: tokens.refresh_token ?? tokens.access_token,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }));
    if (!revoked.ok) return response(502, { error: "Apple couldn't revoke the tokens" });
    return response(200, { revoked: true });
  } catch {
    return response(500, { error: "Revocation failed" });
  }
});
