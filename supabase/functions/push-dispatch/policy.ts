import copy from "./copy.json" with { type: "json" };

// Turns one claimed outbox entry into an APNs request. Pure, so it can be
// tested without Apple or the database. The copy is shared with the app
// (Stop Swiping/Core/Notifications/NotificationCopy.swift); a Swift test
// fails if copy.json drifts from it.

export const bundleID = "Hakketjak.monday-match";

export type Entry = {
  outbox_id: number;
  kind: "match_new" | "first_match" | "message_new" | "match_ended";
  match_id: string;
  count: number;
  token: string;
  environment: "sandbox" | "production";
  partner_name: string | null;
  visible: boolean;
  quiet: boolean;
};

type Template = { id: string; title: string; body: string };
const catalog = copy as Record<string, Template[]>;

export function slot(entry: Entry): string {
  if (entry.kind !== "message_new") return entry.kind;
  const batch = entry.count > 1 ? "_batch" : "";
  return entry.partner_name ? `message_new.preview${batch}` : `message_new.private${batch}`;
}

export function render(text: string, values: Record<string, string>): string {
  return text.replace(/\{(\w+)\}/g, (match, key) => values[key] ?? match);
}

// Variants rotate by outbox row, which spreads them evenly for A/B results.
export function pickTemplate(entry: Entry): Template {
  const templates = catalog[slot(entry)];
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

export function compose(entry: Entry, now = Date.now()): { headers: Record<string, string>; body: string } {
  const data: Record<string, unknown> = { kind: entry.kind, match_id: entry.match_id, dedupe: dedupeKey(entry),
    destination: destination(entry.kind) };
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
  const values = { match_name: entry.partner_name ?? "", count: String(entry.count) };
  const isMessage = entry.kind === "message_new";
  const aps: Record<string, unknown> = {
    alert: { title: render(template.title, values), body: render(template.body, values) },
    "interruption-level": entry.quiet ? "passive" : "active",
    "thread-id": isMessage ? `chat.${entry.match_id}` : "transactional",
    category: "stopswiping.transactional",
    "content-available": 1,
  };
  if (!entry.quiet) aps.sound = "notification-chime.caf";
  // Lets a future Notification Service Extension decrypt and show the text.
  if (isMessage) aps["mutable-content"] = 1;

  headers["apns-push-type"] = "alert";
  headers["apns-priority"] = entry.quiet ? "5" : "10";
  // A newer push for the same conversation replaces the older one.
  headers["apns-collapse-id"] = isMessage ? `chat.${entry.match_id}` : `${entry.kind}.${entry.match_id}`.slice(0, 64);
  return { headers, body: JSON.stringify({ aps, ...data, variant: template.id }) };
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

export function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a), right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return difference === 0;
}
