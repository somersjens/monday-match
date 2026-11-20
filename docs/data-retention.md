# Data retention and server traffic

What the server keeps, for how long, and how the app keeps its requests down.
Migrations: `supabase/migrations/202611190002_traffic_and_retention.sql` and
`202611200002_matching_only_profiles.sql`. Tests:
`supabase/tests/traffic_and_retention.sql`, `matching_only_profiles.sql`.
Edge function: `supabase/functions/retention-purge`.

## Only profiles in automatic matching (since 20 November 2026)

Creating an account backs the profile up to the person's own iCloud
(`ProfileICloudBackup`, CloudKit zone `Profile`, record types `ProfileBackup`
and `ProfileBackupPhoto`, all fields encrypted; both deployed to the
Production schema on 20 November 2026), never to Supabase. The app
sends the profile and its photos to Supabase only while automatic matching is
on. Switching it off calls `leave_matching()`: the profile row goes at once
(out of the pool), the app removes its photos, and the daily job removes
whatever is left a day later. During an active match nothing is removed (the
match continues; the job removes the profile once it ends). Signing in on an
empty phone restores from iCloud first, then from a matching profile on the
server.

What stays on the server after leaving: the account (`auth.users`, needed to
sign in and for purchases), push devices, `matches` rows and
`match_identities` hashes (never the same two people again), and the shared
match history. The phone remembers that its matching photo passed the live
scan, so switching matching back on uploads the photo again and reports the
scan (`DevicePhotoScanReporter`) without a new scan.

The partner's photo is shown by the server only during an active match; the
app keeps the copy it was shown (`MatchPhotoStore`, backed up to iCloud with
the saved match), so it stays visible after a break and goes into a report.

`delete_match(match)` removes an ended match from the caller's own My matches.
The other person keeps it; once both deleted it (or the other account is
gone), its messages, keys, cards and read states go.

## Retention rules (daily job `retention`, 03:29 UTC)

| What | When it goes | How |
| --- | --- | --- |
| Pool entry of a matcher | No sign of the app for 6 months | SQL, `remove_dormant_from_pool()`; the profile stays and the app's next save puts it back |
| Profile and photos outside matching | Auto matching off, no active match, last save over a day ago | `retention_apply('leave')` deletes the row, then the edge function deletes the photos (replaced the 30-day photo rule on 20 November 2026) |
| Profile row, photo, push devices | No sign of the app for 12 months | `retention_apply('profile')`, then the edge function deletes the photos. The sign-in (`auth.users`) stays |
| Stored photos nothing names | After a day | `retention_apply('orphans')`, then the edge function deletes them (failed deletes, replaced photos the app could not remove) |

These come on top of the 12-month purge of messages, cards and reports
(`purge-expired-data`, 202611180003).

"Sign of the app" (`matching_private.last_active`) is the latest of: a
profile save, a sign-in, a session refresh. The app refreshes its token
whenever it opens after an hour away.

**The 28-day rule.** The app trusts what the server last accepted for 28
days (`SupabaseProfileSync.confirmationLifetime`). After that it lists the
account's photos, uploads whatever is missing and saves the profile again,
but only for a profile in auto matching (or one that just left it). The
server never removes anything the phone confirmed within 30 days, so the
phone never names a photo that is gone. The re-save also keeps
`profiles.updated_at` current for everyone who keeps using the app.

If a photo is purged and the person turns auto matching back on later, the
photo is uploaded again and has to be verified again (the verification is
tied to the exact Storage version).

## When the app asks the server

Designed for a pool of a million people: an open app asks only when it is
told something changed. `LiveMatchCenter` has no regular poll.

| Situation | What tells the app | Requests |
| --- | --- | --- |
| No match, pushes working | Push `match_new` / `first_match` → `wake()` → `current_match` | One per new match |
| Opening the app | Asks only if a push arrived while away, a server notification is in Notification Center, or the last answer is over 6 h old (10 min without pushes) | Usually none |
| Active match, app open | Private Realtime channel `match:<id>`: the database sends `message`, `read`, `keys`, `card`, `ended` (kind and who, never content) | One `chat_poll` per message; `current_match` only for a card or the end |
| Channel (re)joins | `connected` → one catch-up refresh (skipped right after one) | One per (re)connect |
| Saving the profile | The server may have matched during the save → one `current_match` | One per real upload |

Fallback timers exist only where nothing else can tell:

- no pushes on this phone (not permitted, or none received for 30 days):
  every 10 minutes while the app is open, without a match;
- a Realtime channel that could not open: every minute with a match;
- a failed request: retried after a minute.

Message pushes are debounced on purpose (15 s, at most one per conversation
per 3 minutes), so an open chat relies on Realtime, not on those pushes. With
the channel open the chat's own loop drops to a safety check every 5 minutes;
without it the chat polls every 3 s while active and 10 s once quiet.

Other savings:

- **`chat_poll`**: one request instead of three (match state, key bundles,
  messages), read receipt included; key bundles only when their fingerprint
  changes.
- **`current_match(p_known_card)`** leaves out the partner's card once the
  phone keeps it.
- **My matches** is kept on the phone (`liveMatch.history.v1`), loaded when
  its list opens and when a match ends. Moderation is checked daily and when
  a match ends (a report ends it).
- **Photos** are resized to 1080 px at JPEG quality 0.78 (was 1600 px / 0.82).
- The app falls back to the old requests when the server answers PGRST202
  (function missing), and to timers when Realtime is not available.

Realtime notes: private channels need the policy "Match participants receive
live signals" on `realtime.messages` (no insert policy: only the database
broadcasts). `realtime.send` silently drops a signal when Realtime has no
partition for the day, which only happens before any client ever connected;
the app catches up on every (re)join anyway.

## Deploying

Steps 1 and 2 were done on 19 November 2026 (52 SQL checks pass live).
On 20 November 2026 `202611200002` replaced step 3: the database created the
Vault secret `retention_secret` itself, and `retention-purge` checks requests
with `retention_secret_matches()` instead of a `RETENTION_SECRET` copy
(43 SQL checks pass live; the function was redeployed). Still by hand: turn
"Verify JWT with legacy secret" off for `retention-purge`, or pg_net's call
(which carries no JWT) is refused.

1. SQL editor: run the migration (see the supabase-deploy notes), then the
   test file ("Run without RLS"; everything rolls back).
2. Edge Functions → new function `retention-purge` with `index.ts`, then
   turn "Verify JWT with legacy secret" **off** for it (still to do by hand).
3. Make a random secret (for example `openssl rand -hex 32`) and store it twice:
   - Edge Function secret `RETENTION_SECRET`;
   - SQL: `select vault.create_secret('<secret>', 'retention_secret');`
4. Check after a day: `select * from cron.job_run_details where jobid =
   (select jobid from cron.job where jobname = 'retention') order by start_time desc limit 3;`
   and the function's logs (counts only).

Until step 3 is done, the job only takes dormant matchers out of the pool.
Do step 3 only once testers run a build with the 28-day rule; an older build
could name a photo the job removed.

## Not covered yet

- The privacy policy's retention table (`PrivacyContent.swift`) now states
  the matching-profile, iCloud and message rules (20 November 2026); the
  account, log, report and consent rows still have placeholders.
- `profiles.profile` and `profiles.backup` overlap (about 6 and 12 kB); the
  matching functions read both, so merging them is a larger change.
