import { createClient } from "npm:@supabase/supabase-js@2.95.3";

// Removes what the retention rules no longer allow the server to keep
// (supabase/migrations/202611190002_traffic_and_retention.sql):
//   profile  no sign of the app for 12 months: profile row, photos, push devices
//   photos   automatic matching off for 30 days: the photo
//   orphans  stored photos nothing has named for a day
// The database decides and changes the rows (retention_apply); this function
// only deletes Storage objects, which SQL may not. Called once a day by
// pg_cron, never by the app. Secret: RETENTION_SECRET. Logs counts only.

const response = (status: number, body: object) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a), right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) difference |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return difference === 0;
}

type Due = { user_id: string; action: "profile" | "photos" | "orphans" };

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, { error: "POST required" });
  const secret = Deno.env.get("RETENTION_SECRET");
  if (!secret || !constantTimeEqual(request.headers.get("X-Retention-Secret") ?? "", secret)) {
    return response(401, { error: "Not allowed" });
  }
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } });

  const counts = { profile: 0, photos: 0, orphans: 0, objects: 0, failed: 0 };
  // A few batches per run; whatever is left is still due tomorrow.
  for (let batch = 0; batch < 5; batch++) {
    const { data, error } = await admin.rpc("retention_claim", { p_limit: 100 });
    if (error) return response(500, { error: "Claim failed", counts });
    const due = (data ?? []) as Due[];
    if (due.length === 0) break;
    let progressed = false;
    for (const item of due) {
      const { data: names, error: applyError } = await admin.rpc("retention_apply",
        { p_user_id: item.user_id, p_action: item.action });
      if (applyError) { counts.failed++; continue; }
      counts[item.action]++;
      progressed = true;
      const paths = (names ?? []) as string[];
      for (let i = 0; i < paths.length; i += 100) {
        const { error: removeError } = await admin.storage.from("profile-photos").remove(paths.slice(i, i + 100));
        // Left for tomorrow's run as 'orphans': no row names them any more.
        if (removeError) counts.failed++;
        else counts.objects += Math.min(100, paths.length - i);
      }
    }
    if (!progressed) break;
  }
  console.log(JSON.stringify(counts));
  return response(200, counts);
});
