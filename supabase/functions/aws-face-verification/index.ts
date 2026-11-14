import { createClient } from "npm:@supabase/supabase-js@2.95.3";
import { RekognitionClient, CreateFaceLivenessSessionCommand, GetFaceLivenessSessionResultsCommand,
  DetectFacesCommand, CompareFacesCommand } from "npm:@aws-sdk/client-rekognition@3.1010.0";
import { STSClient, AssumeRoleCommand } from "npm:@aws-sdk/client-sts@3.1010.0";
import { CONSENT, MINIMUM_SIMILARITY, REGION, passesVerification, uuid } from "./policy.ts";

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
// No request bodies, AWS responses, credentials or image bytes are logged.
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return response(401, { error: "Authentication required" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return response(401, { error: "Authentication required" });
  const accessKeyId = Deno.env.get("AWS_ACCESS_KEY_ID"), secretAccessKey = Deno.env.get("AWS_SECRET_ACCESS_KEY");
  const streamRole = Deno.env.get("AWS_LIVENESS_STREAM_ROLE_ARN");
  if (!accessKeyId || !secretAccessKey || !streamRole) return response(503, { error: "AWS verification is not configured yet" });
  const credentials = { accessKeyId, secretAccessKey, sessionToken: Deno.env.get("AWS_SESSION_TOKEN") };
  const aws = new RekognitionClient({ region: REGION, credentials });
  const sts = new STSClient({ region: REGION, credentials });
  try {
    if (Number(request.headers.get("Content-Length") ?? 0) > 2048) return response(413, { error: "Request too large" });
    const raw = await request.text();
    if (raw.length > 2048) return response(413, { error: "Request too large" });
    const body = JSON.parse(raw);
    const userID = auth.user.id;
    if (body.action === "start") {
      if (!uuid(body.photo_id) || body.consent_version !== CONSENT) return response(400, { error: "Photo and consent required" });
      // Use the caller's JWT for the admission/rate-limit RPC, never an asserted user ID.
      const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false },
      });
      const { data: attempt, error } = await caller.rpc("begin_photo_verification", {
        p_photo_id: body.photo_id, p_consent_version: CONSENT,
      });
      if (error) return response(409, { error: "Photo unavailable or daily verification limit reached" });
      const created = await aws.send(new CreateFaceLivenessSessionCommand({
        ClientRequestToken: attempt.request_id, Settings: { AuditImagesLimit: 0 },
      }));
      if (!created.SessionId) throw new Error("Session unavailable");
      const { error: bindError } = await admin.rpc("bind_photo_verification_session", {
        p_request_id: attempt.request_id, p_user_id: userID, p_session_id: created.SessionId,
      });
      if (bindError) throw new Error("Session binding failed");
      const temporary = await sts.send(new AssumeRoleCommand({
        RoleArn: streamRole, ExternalId: new URL(url).hostname.split(".")[0], RoleSessionName: `liveness-${attempt.request_id}`, DurationSeconds: 900,
        Policy: JSON.stringify({ Version: "2012-10-17", Statement: [{ Effect: "Allow",
          Action: "rekognition:StartFaceLivenessSession", Resource: "*", Condition: { StringEquals: { "aws:RequestedRegion": REGION } } }] }),
      }));
      const c = temporary.Credentials;
      if (!c?.AccessKeyId || !c.SecretAccessKey || !c.SessionToken || !c.Expiration) throw new Error("Temporary credentials unavailable");
      return response(200, { request_id: attempt.request_id, session_id: created.SessionId, region: REGION,
        expires_at: attempt.expires_at, credentials: { access_key: c.AccessKeyId, secret_key: c.SecretAccessKey,
          session_token: c.SessionToken, expiration: c.Expiration.toISOString() } });
    }
    if (body.action !== "complete" || !uuid(body.request_id)) return response(400, { error: "Invalid action" });
    const { data: attempt, error } = await admin.rpc("photo_verification_worker_request", {
      p_request_id: body.request_id, p_user_id: userID,
    });
    if (error || !attempt) return response(404, { error: "Verification unavailable" });
    if (!attempt.photo_current) return response(409, { error: "Selected photo changed; start again" });
    if (attempt.status === "verified") return response(200, { verified: true });
    if (attempt.status !== "pending" || !attempt.aws_session_id || Date.parse(attempt.expires_at) <= Date.now())
      return response(409, { error: "Verification expired; start again" });
    const result = await aws.send(new GetFaceLivenessSessionResultsCommand({ SessionId: attempt.aws_session_id }));
    if (result.Status === "CREATED" || result.Status === "IN_PROGRESS") return response(202, { verified: false, pending: true });
    let faces = 0, similarities: number[] = [];
    if (result.Status === "SUCCEEDED" && result.ReferenceImage?.Bytes && (result.Confidence ?? 0) >= 95) {
      const { data: image, error: downloadError } = await admin.storage.from("profile-photos").download(attempt.path);
      if (downloadError || !image || image.size > 5 * 1024 * 1024) return response(409, { error: "Photo unavailable or too large" });
      const photo = new Uint8Array(await image.arrayBuffer());
      const detected = await aws.send(new DetectFacesCommand({ Image: { Bytes: photo }, Attributes: ["DEFAULT"] }));
      faces = detected.FaceDetails?.length ?? 0;
      if (faces === 1) {
        const comparison = await aws.send(new CompareFacesCommand({ SourceImage: { Bytes: result.ReferenceImage.Bytes },
          TargetImage: { Bytes: photo }, SimilarityThreshold: MINIMUM_SIMILARITY, QualityFilter: "AUTO" }));
        similarities = (comparison.FaceMatches ?? []).map((x) => x.Similarity ?? 0);
      }
    }
    const passed = passesVerification(result.Status, result.Confidence, faces, similarities);
    const { data: verified, error: completionError } = await admin.rpc("complete_photo_verification", {
      p_request_id: body.request_id, p_user_id: userID, p_session_id: attempt.aws_session_id, p_passed: passed,
    });
    if (completionError) return response(409, { error: "Photo or session changed; start again" });
    return response(200, { verified: verified === true });
  } catch {
    return response(502, { error: "Verification service unavailable. Start a new check or try again shortly." });
  } finally {
    aws.destroy(); sts.destroy();
  }
});
