# Supabase matching backend

The whole database (profiles, photos, matching, chat, moderation and photo
verification) is one migration: `supabase/migrations/202611160001_baseline.sql`.
Apply it once to an empty Supabase project through the SQL Editor.

It replaces the ten migrations from 14–15 November 2026, merged before launch
on 16 November 2026. The live Stop Swiping project already has this schema
(it was built by those ten): **do not run the baseline against it**. Before
the merge the baseline was compared with the live database: all 37 function
bodies (36 byte-for-byte; `set_profile_updated_at` only differs in line
breaks), every table, column, default, constraint, index, policy, trigger,
comment, privilege and the admin view match. Manual SQL Editor application
does not register versions in the Supabase CLI migration history; reconcile
that history before adopting CLI deployment for this project.

## Admission and lifecycle

Every insert or update of `profiles.profile` / `profiles.backup` runs the engine
inside the same transaction, so the app's normal profile sync is what enters
someone into matching. A failed match transaction rolls back the profile save
and can be retried.

Admission requires a completed adult profile, both current privacy receipts,
auto-matching enabled, valid matching settings, all 50 personality answers, all
three substance answers, and no active block or ban. Missing or malformed data
stays backed up but does not enter the pool. An unrestricted height range is
encoded by the app as absent bounds and means 50–250 cm.

1. Already matched: return the existing match ID.
2. Build the pool entry: every requirement as a plain column, the 50 answers as
   three small integer arrays (own answer, wanted answer, weight), the sign-in
   identity hashes and an `inputs_hash` of all of it.
3. Already waiting with the same `inputs_hash` (a save that changed nothing the
   matcher uses): stop. Every arrival since already compared itself with this
   entry, so a new search cannot find anyone. This keeps routine syncs free.
4. Otherwise keep the original queue time and search with one SQL query: cheap
   column filters first (gender both ways and the age window, which use the
   `pool_gender_birth` index, plus a latitude box), then every hard requirement
   both ways (`meets_requirements`), the verified-photo preference, both personal
   minimum scores, and never anyone this person was matched with before.
5. Highest sum of both scores wins; equal sums prefer the longest-waiting
   candidate, then UUID. Insert the match, reserve both people, store both
   identity hashes with it and remove both from the pool atomically.

Matching, breaking, moderation and photo verification share one transaction
advisory lock. Chat does not take it any more: `send_encrypted_message` and
`register_chat_device` take a share lock on the match row, which `break_match`
must update, so a message lands either before the break or not at all. A primary
key on `matched_users` independently prevents double booking.

### At most one search per account per minute

Because the lock is shared, one account saving over and over (for example by
calling the API directly) could hold up matching for everyone. Since
`202611180005_matching_throttle.sql`:

* a save that changes neither `profile` nor `backup` returns at once, without the lock;
* the first change searches immediately;
* further changes within the same minute only refresh the person's pool entry
  (switching matching off still removes them at once) and mark the search as
  pending in `matching_private.search_state`;
* the pg_cron job `matching-pending-searches` (every 20 s) runs pending searches
  once their minute is over. `retry_matching` follows the same rule.

Trusted callers (photo verification, breaking a match, moderation, admin) call
`try_match` directly and still search at once. A held-back person can still be
found by others in the meantime; at worst their own search runs about a minute
later. SQL tests switch the limit off with
`set local stop_swiping.matching_throttle = 'off'`, which only works in a
session opened as `postgres`.

### Retention

The pg_cron job `purge-expired-data` (daily, 03:17 UTC) runs
`matching_private.purge_expired()` (`202611180003_retention_and_identity_hmac.sql`):
messages go 12 months after they were sent, also in a broken match; matches that
ended more than 12 months ago lose their cards, keys and read positions (the
match row stays for the pair exclusion); a report's written explanation is
blanked after 12 months while the strike keeps counting.

### Never the same two people again

`unique (user_low, user_high)` blocks the same two accounts. In addition each
match stores a keyed hash (HMAC-SHA256 with the Vault secret
`identity_hash_key`; never rotate it without rehashing) of both people's sign-in
identities (provider + subject, e.g. their Apple ID) in
`matching_private.match_identities`. Someone who deletes
their account and signs up again with the same Apple or Google account is still
never matched with anyone they were matched with before. Off/on toggles,
profile edits, retries and every way a match can end keep the exclusion.

### Breaking, and the history after it

`break_match` (either participant) records who broke it and when, frees both
people and immediately lets both search again if their saved opt-in is still
on. The conversation stays: `my_matches()` lists every match, active and broken,
and the encrypted messages and key bundles stay readable for both participants.
No new message or device can be added to a broken match. In the app a broken
match appears under **My matches** with "Match" struck through; opening it shows
the match heart, the partner's profile, and the conversation where a non-match
lists its reasons. Tapping the conversation opens it in full, read-only.

### Deleting a profile or account

Deleting a profile ends its active match with `profile_deleted` and lets the
partner search again straight away. Participant IDs stay in the match and on
their messages (no foreign keys to `auth.users` there), so the survivor keeps
the pair exclusion and can still decrypt the conversation they took part in.
The deleted account's profile, match card, read state and reports it filed (the
reporter is set to null; the report keeps counting) go with it. When both
participants are gone, `matching_private.account_deleted` removes the
conversation's messages, keys, cards and read states.

### Reports: warning, 7-day block, ban

`report_partner` stores a report about the other participant. Only the first
report per match counts as a strike, so one person can add at most one strike
to someone (two people can match only once). Strikes follow the reported
person's sign-in identity hashes, so a new account with the same Apple or Google
ID keeps them.

| Strikes | Consequence |
| --- | --- |
| 1 | Warning. Matching and the current conversation continue. |
| 2 | Blocked for 7 days from the second report: the current match ends (`moderation`, or `reported` when the reporter broke it), the person leaves the pool and is not admitted again until the block ends. Their next profile sync after that re-admits them. |
| 3 | Banned: as above, permanently. Signing up again with the same sign-in stays banned. |

`matching_status()` returns `moderation: {strikes, strikes_seen, suspended_until,
banned}`; the app shows a notice once per new strike and calls
`acknowledge_moderation()`. An administrator can withdraw an unfounded report
with `select matching_private.dismiss_report('<report id>')`, which lifts a block
or ban it caused and lets the person search again.

## Requirements and scores

Both directions enforce gender, age, height, religion/worldview, at least one
shared language, distance, children/future children, substance frequency limits,
appearance minimum, and the verified-photo preference. The sexual arrangement
selection must overlap as well. The latter and appearance/photo requirements
are additional automatic-matching checks beyond the local exchange report.

The 50 question IDs match `CompatibilityScaleQuestion`. Scores use the local
`MatchReport` formula: weights 0/1/2/4/8 for importance 1–5, linear closeness
over the four-step personality scale. Alcohol, smoking and drugs are hard
limits only and do not influence the percentage. Each direction must meet that user's own
minimum percentage; an average cannot conceal one failing direction. Both
scores and the algorithm version are frozen in the match row.

Distance uses the rounded coordinates already uploaded by the app, with a
spherical Haversine calculation. Age is evaluated on the database's current
date. Values close to a distance/age boundary may differ from the device's
precise Core Location calculation or local calendar date. No precise device
coordinates are added by this change.

## Inspecting the live system

As project administrator in SQL Editor:

The saved private query **Matching – overzicht** opens this overview in the
live dashboard.

```sql
select * from matching_private.overview order by display_name;
select id, user_low, user_high, score_low, score_high,
       matched_at, ended_at, ended_by, end_reason
from public.matches order by matched_at desc;
```

The private overview shows each user's opt-in, waiting/matched/disabled/ineligible
state, current partner, match ID, queue timestamp, match-history count and photo
verification status. It is inaccessible to ordinary clients. Do not expose
`matching_private` through the Data API.

Authenticated client operations:

| Operation | API |
| --- | --- |
| Read own state and moderation | `rpc("matching_status")` |
| Acknowledge the newest moderation notice | `rpc("acknowledge_moderation")` |
| Search again now | `rpc("retry_matching")` |
| The active match for the home screen | `rpc("current_match")` |
| Every match, active and broken | `rpc("my_matches")` |
| Break a match | `rpc("break_match", {p_match_id})` |
| Report the other participant | `rpc("report_partner", {p_match_id, p_reason, p_details, p_break_match})` |
| Register this device's public key | `rpc("register_chat_device", {p_match_id, p_device_id, p_public_bundle, p_replace_device})` |
| Read both participants' bundles | `from("match_key_bundles").select().eq("match_id", matchID)` |
| Store encrypted envelope | `rpc("send_encrypted_message", {p_match_id, p_client_message_id, p_sender_device_id, p_recipient_device_id, p_ciphertext, p_protocol_version: "hpke-auth-x25519-v1"})` |
| Read encrypted history | `from("encrypted_messages").select().eq("match_id", matchID).gt("id", cursor).order("id").limit(100)` |

`matching_status` returns `{state, match_id, photo_verified, moderation}` where state is `matched`, `banned`, `suspended`, `waiting`, `ineligible` or `disabled`. History contains
`user_low` and `user_high`; the other ID is the conversation partner. RLS filters
all three public tables to those two participants. Anonymous access and direct
client writes are denied; mutation functions derive the sender from `auth.uid()`.
Profile backups and private photos remain readable only by their owners: this
migration does not expose their complete backup to a match.

## Photo verification boundary

The existing face check runs locally. Its receipt is deliberately excluded from
the cloud backup and cannot prove server-side verification. Consequently there
are **no trusted verified photos by default**. Users who require verified partner
photos (the app's default) wait until a trusted verifier is connected. Users who
opt out of that requirement can match without a photo.

A trusted database worker may write `matching_private.photo_verifications`
after actually validating the selected uploaded image. Store its Storage object
ID and exact `storage.objects.updated_at` value captured for the verified bytes.
After attestation call `matching_private.try_match(userID)` in the same trusted
workflow to search again. A replaced object/version or a different selected photo
does not inherit verification. Do not accept an arbitrary client-supplied flag,
timestamp, or local receipt as a trusted attestation.

## Live chat and E2EE

The real profile home polls the current server match while foregrounded and opens
its live conversation. There is no preloaded mock match in the signed-in root.
Chat sends/receives encrypted messages, retries pending envelopes after network
failure, and synchronizes ending/blocking and reports to the backend. Polling is
foreground-only (3 seconds for chat, 5 for match discovery). Pushes for new
matches, messages and ended matches are queued by
`202611160002_push_notifications.sql` and sent by the `push-dispatch` function;
see [notifications](notifications.md). They carry no message content.

`ChatCryptography` uses Apple's RFC 9180 authenticated HPKE with X25519,
HKDF-SHA256 and ChaCha20-Poly1305. Each message creates fresh HPKE encapsulations
for the recipient and the sender's own history copy. Match ID, message ID,
sender account and both device IDs are authenticated. Messages can be received
out of order. The server stores only the opaque envelope and delivery metadata.
This uses CryptoKit's standard implementation; no custom cipher was introduced.

Keys are generated per project/account/match/device and kept in Keychain with
`WhenUnlockedThisDeviceOnly`. They are not synced to iCloud. Unacknowledged
outgoing ciphertexts (never plaintext) persist there with their original UUID
and bytes, so a lost acknowledgement cannot produce a duplicate message.
Plaintext exists only in app memory; it is neither logged nor cloud-backed up.

A first peer key is pinned on first use. Users can compare the same security
code by phone/in person and mark it checked. A changed peer device stops sending
until the new code is explicitly checked. Device keys are immutable; replacement
requires a new device UUID. The server permits one active device per participant
per match. Explicitly switching devices revokes the old device for future sends;
old public bundles remain for history. Keys available on the same phone are
archived locally when rotating; history from a lost/other phone cannot be
recovered automatically. The UI discloses unsent-message discards when switching
or accepting a changed peer device.

This is **not Signal's Double Ratchet**: there is no automatic multi-device
fan-out, forward-secrecy ratchet or post-compromise recovery. Compromise of a
retained recipient conversation key can expose that conversation's recorded
history. A first-use server substitution is detectable by comparing security
codes; pinning alone cannot establish the initial human identity. Do not market
stronger properties than those implemented. Have the E2EE/key-lifecycle design
reviewed before public release.

The database independently rejects nonparticipants, ended matches and revoked
sender/recipient devices. Ciphertext sizes are bounded and reused delivery IDs
cannot change content. The backend cannot prove a client-supplied string was
encrypted; the app's cryptographic path enforces it. Legacy `e2ee-v1` is retained
for existing transport rows; the live client uses `hpke-auth-x25519-v1`.

## Photo verification

During the beta the automatic-matching photo is verified by the app's own live
scan on the phone ([photo verification](face-verification.md)). After a match the
app calls `record_device_photo_verification(p_photo_id)`
(`202611180002_device_photo_verification.sql`). It checks the caller's selected
photo, current privacy consent and stored object, records that exact object
version in `matching_private.photo_verifications` with `method = 'device'`, and
re-runs matching. `has_verified_photo` is unchanged, so device and AWS records
both count. The server cannot prove the scan happened; that is the accepted
beta trade-off.

AWS Face Liveness (server-proven) is parked; see
[AWS photo verification](aws-photo-verification.md) for how to turn it back on.

## Validation and scaling

Two SQL files run as `postgres` in SQL Editor ("Run without RLS"). Each creates
isolated fixtures inside a transaction, switches to `authenticated` for the
authorization checks, asserts, and rolls back:

* `supabase/tests/matching_regression.sql`: admission, scoring, ranking, pair
  exclusion, device rotation, E2EE storage rules and AWS photo verification.
* `supabase/tests/lifecycle_moderation.sql`: the whole lifecycle end to end —
  pool entry, skipped unchanged saves, automatic match, chat, breaking, readable
  history, account deletion, recreated accounts, and warning → block → ban,
  dismissal and ban evasion.

Both switch the one-minute search limit off; its own checks are at the end of
`matching_regression.sql`. On 18 November 2026 the lifecycle file (72) and the
limit checks (9) passed against the live project after `202611180005`.

On 15 November 2026 both passed against the live project:
**85** and **72** assertions, with zero fixture accounts, profiles, matches,
reports or pool entries left afterwards.

Matching still serializes writers behind one lock, and a search reads the whole pool (cheaply: plain columns and integer arrays, no JSON parsing). It is suited
to validating the first real pool; it has not been load-tested with concurrent
clients. At scale, normalize/index admission/filter fields, reduce candidate
scans, replace the global lock with a proven reservation strategy, add request
rate limits and operational metrics, and test concurrency under load. Retry
transient transaction failures. Avoid adding global workers that silently
recreate history or override users' requirements.

References: [Supabase database functions](https://supabase.com/docs/guides/database/functions)
and [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
