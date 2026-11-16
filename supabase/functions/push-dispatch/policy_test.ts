import { classify, compose, constantTimeEqual, dedupeKey, type Entry, slot } from "./policy.ts";
const assert = (value: boolean, message = "Assertion failed") => { if (!value) throw new Error(message); };

const base: Entry = {
  outbox_id: 7, kind: "message_new", match_id: "a7fa0000-0000-4000-8000-000000000001", count: 1,
  token: "ab".repeat(32), environment: "sandbox", partner_name: "Sam", visible: true, quiet: false,
};

Deno.test("previews decide whether a name reaches the lock screen", () => {
  const named = JSON.parse(compose(base).body);
  assert(named.aps.alert.title === "Sam");
  assert(named.aps.alert.body.includes("Sam"));
  const hidden = JSON.parse(compose({ ...base, partner_name: null }).body);
  assert(!JSON.stringify(hidden.aps).includes("Sam"));
  assert(hidden.aps.alert.title === "New message");
});

Deno.test("a burst becomes one push that counts and replaces the previous one", () => {
  assert(slot({ ...base, count: 3 }) === "message_new.preview_batch");
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
