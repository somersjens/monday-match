import { classify, classifyFCM, compose, composeFCM, constantTimeEqual, dedupeKey, type Entry, slot } from "./policy.ts";
const assert = (value: boolean, message = "Assertion failed") => { if (!value) throw new Error(message); };

const base: Entry = {
  outbox_id: 7, kind: "message_new", match_id: "a7fa0000-0000-4000-8000-000000000001", count: 1,
  platform: "ios", token: "ab".repeat(32), environment: "sandbox", previews: true, visible: true, quiet: false,
};

Deno.test("no push carries a name; previews only wake the extension", () => {
  const preview = JSON.parse(compose(base).body);
  assert(preview.aps.alert.title === "New message" || preview.aps.alert.title === "You've got a message");
  assert(!("partner_name" in preview) && !JSON.stringify(preview).includes("{match_name}"));
  assert(preview.aps["mutable-content"] === 1 && preview.preview === "1");
  const hidden = JSON.parse(compose({ ...base, previews: false }).body);
  assert(hidden.aps["mutable-content"] === undefined && hidden.preview === "0");
});

Deno.test("Dutch devices get the Dutch copy, others fall back to English", () => {
  const dutch = JSON.parse(compose({ ...base, language: "nl" }).body);
  assert(dutch.aps.alert.title === "Nieuw bericht" || dutch.aps.alert.title === "Er is post");
  assert(dutch.variant.includes(".nl."));
  const unknown = JSON.parse(compose({ ...base, language: "fr" as "nl" }).body);
  assert(unknown.aps.alert.title === "New message" || unknown.aps.alert.title === "You've got a message");
});

Deno.test("a burst becomes one push that counts and replaces the previous one", () => {
  assert(slot({ ...base, count: 3 }) === "message_new.private_batch");
  const { headers, body } = compose({ ...base, count: 3 });
  assert(JSON.parse(body).aps.alert.body.includes("3"));
  assert(headers["apns-collapse-id"] === `chat.${base.match_id}`);
  assert(JSON.parse(body).aps["mutable-content"] === 1);
});

Deno.test("quiet hours arrive silently", () => {
  const { headers, body } = compose({ ...base, quiet: true });
  const aps = JSON.parse(body).aps;
  assert(aps["interruption-level"] === "passive");
  assert(aps.sound === undefined);
  assert(headers["apns-priority"] === "5");
});

Deno.test("match ended without alerts is a background push that shows nothing", () => {
  const { headers, body } = compose({ ...base, kind: "match_ended", visible: false });
  const payload = JSON.parse(body);
  assert(headers["apns-push-type"] === "background");
  assert(payload.aps.alert === undefined);
  assert(payload.dedupe === `match_ended.${base.match_id}`);
});

Deno.test("matches share the app's dedupe key and never mention a name", () => {
  for (const kind of ["match_new", "first_match"] as const) {
    const payload = JSON.parse(compose({ ...base, kind }).body);
    assert(dedupeKey({ ...base, kind }) === `match_new.${base.match_id}`);
    assert(!JSON.stringify(payload.aps).includes("Sam"));
    assert(!/likes? you/i.test(JSON.stringify(payload.aps)));
  }
});

Deno.test("APNs answers map to revoke, retry or done", () => {
  assert(classify(200) === "sent");
  assert(classify(410) === "revoke");
  assert(classify(400, "BadDeviceToken") === "revoke");
  assert(classify(429) === "retry");
  assert(classify(503) === "retry");
  assert(classify(400, "PayloadTooLarge") === "failed");
});

Deno.test("the dispatch secret is compared in constant time", () => {
  assert(constantTimeEqual("secret", "secret"));
  assert(!constantTimeEqual("secret", "secreT"));
  assert(!constantTimeEqual("secret", "secret-longer"));
});

Deno.test("Android gets a data message with the same facts and no name", () => {
  const { message } = composeFCM({ ...base, platform: "android", token: "fcm:token", count: 2 });
  const data = message.data as Record<string, string>;
  const android = message.android as Record<string, string>;
  assert(message.token === "fcm:token" && !("notification" in message));
  assert(data.kind === "message_new" && data.count === "2" && data.preview === "1" && data.visible === "1");
  assert(Object.values(data).every((value) => typeof value === "string"), "FCM data values are strings");
  assert(data.dedupe === dedupeKey(base) && android.collapse_key === `chat.${base.match_id}`);
  assert(android.priority === "HIGH" && android.ttl === "86400s");
  assert(!JSON.stringify(message).includes("Sam") && !JSON.stringify(message).includes("{match_name}"));
  const quiet = composeFCM({ ...base, platform: "android", quiet: true }).message.android as Record<string, string>;
  assert(quiet.priority === "NORMAL");
  const silent = composeFCM({ ...base, platform: "android", kind: "match_ended", visible: false }).message;
  assert((silent.data as Record<string, string>).title === undefined);
});

Deno.test("FCM answers map to revoke, retry or done", () => {
  assert(classifyFCM(200) === "sent");
  assert(classifyFCM(404, "UNREGISTERED") === "revoke");
  assert(classifyFCM(403, "SENDER_ID_MISMATCH") === "revoke");
  assert(classifyFCM(401) === "retry");
  assert(classifyFCM(429, "QUOTA_EXCEEDED") === "retry");
  assert(classifyFCM(503) === "retry");
  assert(classifyFCM(400, "INVALID_ARGUMENT") === "failed");
});
