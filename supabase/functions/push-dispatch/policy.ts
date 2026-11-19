import copy from "./copy.json" with { type: "json" };

// Turns one claimed outbox entry into an APNs (iOS) or FCM (Android) request.
// Pure, so it can be tested without Apple, Google or the database. The copy
// is shared with the app (Stop Swiping/Core/Notifications/NotificationCopy.swift);
// a Swift test fails if copy.json drifts from it.
//
// Apple and Google can read every payload, so a push never carries a name or
// message content: only what happened (kind, match, count). With previews on,
// the phone puts the name on the lock screen itself: the iOS Notification
// Service Extension, or the Android app's data-message handler.

export const bundleID = "Hakketjak.monday-match";

export type Platform = "ios" | "android";

export type Entry = {
  outbox_id: number;
  kind: "match_new" | "first_match" | "message_new" | "match_ended";
  match_id: string;
  count: number;
  // Missing on rows claimed before 202611190010: those were all iOS.
  platform?: Platform;
  token: string;
  environment: "sandbox" | "production";
  // The app's language. Each has its own copy, written rather than translated.
  language?: "en" | "nl";
  // The device's "Message previews" switch. The phone fills in the name.
  previews?: boolean;
  visible: boolean;
  quiet: boolean;
};

type Template = { id: string; title: string; body: string };
const catalogs = copy as Record<string, Record<string, Template[]>>;

export const platformOf = (entry: Entry): Platform => entry.platform ?? "ios";

// The server only ever sends copy without a name. The preview slots in
// copy.json are used on the phone, which knows the name.
export function slot(entry: Entry): string {
  if (entry.kind !== "message_new") return entry.kind;
  return entry.count > 1 ? "message_new.private_batch" : "message_new.private";
}

export function render(text: string, values: Record<string, string>): string {
  return text.replace(/\{(\w+)\}/g, (match, key) => values[key] ?? match);
}

// Variants rotate by outbox row, which spreads them evenly for A/B results.
export function pickTemplate(entry: Entry): Template {
  const templates = (catalogs[entry.language ?? "en"] ?? catalogs.en)[slot(entry)] ?? catalogs.en[slot(entry)];
  if (!templates?.length) throw new Error(`No copy for ${slot(entry)}`);
  return templates[Math.abs(entry.outbox_id) % templates.length];
}

const destination = (kind: Entry["kind"]) =>
  kind === "message_new" ? "stopswiping://open/chat"
    : kind === "match_ended" ? "stopswiping://open/matches" : "stopswiping://open/match";

// The key the app uses to recognise a notification it already showed.
export function dedupeKey(entry: Entry): string {
  switch (entry.kind) {
    case "match_new": case "first_match": return `match_new.${entry.match_id}`;
    case "match_ended": return `match_ended.${entry.match_id}`;
    case "message_new": return `message_new.${entry.match_id}.${entry.outbox_id}`;
  }
}

// A newer push for the same conversation replaces the older one.
const collapseKey = (entry: Entry) =>
  (entry.kind === "message_new" ? `chat.${entry.match_id}` : `${entry.kind}.${entry.match_id}`).slice(0, 64);

// What both platforms receive besides the visible text. Strings only, as FCM requires.
function facts(entry: Entry): Record<string, string> {
  const wantsPreview = entry.kind === "message_new" && entry.previews === true;
  return {
    kind: entry.kind, match_id: entry.match_id, dedupe: dedupeKey(entry), destination: destination(entry.kind),
    count: String(entry.count), outbox_id: String(entry.outbox_id), preview: wantsPreview ? "1" : "0",
  };
}

export function compose(entry: Entry, now = Date.now()): { headers: Record<string, string>; body: string } {
  const data = facts(entry);
  const headers: Record<string, string> = {
    "apns-topic": bundleID,
    // Stale news is no news: a match or message push is pointless after a day.
    "apns-expiration": String(Math.floor(now / 1000) + 86_400),
  };

  if (!entry.visible) {
    // Background only: lets the app replan its reminders, shows nothing.
    headers["apns-push-type"] = "background";
    headers["apns-priority"] = "5";
    return { headers, body: JSON.stringify({ aps: { "content-available": 1 }, ...data }) };
  }

  const template = pickTemplate(entry);
  const values = { count: String(entry.count) };
  const isMessage = entry.kind === "message_new";
  const aps: Record<string, unknown> = {
    alert: { title: render(template.title, values), body: render(template.body, values) },
    "interruption-level": entry.quiet ? "passive" : "active",
    "thread-id": isMessage ? `chat.${entry.match_id}` : "transactional",
    category: "stopswiping.transactional",
    "content-available": 1,
  };
  if (!entry.quiet) aps.sound = "notification-chime.caf";
  // Wakes the Notification Service Extension, which adds the name.
  if (data.preview === "1") aps["mutable-content"] = 1;

  headers["apns-push-type"] = "alert";
  headers["apns-priority"] = entry.quiet ? "5" : "10";
  headers["apns-collapse-id"] = collapseKey(entry);
  return { headers, body: JSON.stringify({ aps, ...data, variant: template.id }) };
}

// FCM HTTP v1. Always a data message: the Android app builds the
// notification itself, so it can add the name (and, later, a decrypted
// preview) and apply its own channels, exactly like the iOS extension.
export function composeFCM(entry: Entry): { message: Record<string, unknown> } {
  const data: Record<string, string> = { ...facts(entry), visible: entry.visible ? "1" : "0",
    quiet: entry.quiet ? "1" : "0", language: entry.language ?? "en" };
  if (entry.visible) {
    const template = pickTemplate(entry);
    const values = { count: String(entry.count) };
    Object.assign(data, { title: render(template.title, values), body: render(template.body, values),
      variant: template.id });
  }
  return {
    message: {
      token: entry.token,
      data,
      android: {
        priority: entry.visible && !entry.quiet ? "HIGH" : "NORMAL",
        ttl: "86400s",
        collapse_key: collapseKey(entry),
      },
    },
  };
}

export type Outcome = "sent" | "retry" | "revoke" | "failed";

// What to do with APNs' answer.
export function classify(status: number, reason?: string): Outcome {
  if (status === 200) return "sent";
  if (status === 410) return "revoke";
  if (status === 400 && ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(reason ?? "")) return "revoke";
  if (status === 429 || status >= 500) return "retry";
  if (status === 403 && ["ExpiredProviderToken", "InvalidProviderToken"].includes(reason ?? "")) return "retry";
  return "failed";
}

// What to do with FCM's answer. `code` is the FcmError errorCode from the
// response details, when there is one.
export function classifyFCM(status: number, code?: string): Outcome {
  if (status === 200) return "sent";
  if (status === 404 || code === "UNREGISTERED") return "revoke";
  if (status === 403 && code === "SENDER_ID_MISMATCH") return "revoke";
  if (status === 401) return "retry"; // access token expired; a fresh one is fetched
  if (status === 429 || status >= 500 || code === "QUOTA_EXCEEDED" || code === "UNAVAILABLE" || code === "INTERNAL") {
    return "retry";
  }
  return "failed";
}

export function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a), right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return difference === 0;
}
