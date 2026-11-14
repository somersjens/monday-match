# Supabase matching backend

Migrations `202611140002_matching.sql` through `202611140006_aws_photo_verification.sql`
extend the existing private profile backup. Apply them once, in order, after
`202611140001_profiles.sql`. Migrations 002–005 were applied manually to the Stop Swiping
Supabase project on 14 November 2026 through its SQL Editor. Do not replay them
against that project. Manual SQL Editor application does not register versions
in the Supabase CLI migration history; reconcile that history before adopting
CLI deployment for this existing project.

## Admission and lifecycle

Every insert or update of `profiles.profile` / `profiles.backup` runs the engine
inside the same transaction. The iOS app's existing profile synchronization
therefore activates matching without a second network request. A failed match
transaction also rolls back the profile update and can be retried by the app.

Admission requires a completed adult profile, both current privacy receipts,
auto-matching enabled, valid matching settings, all 50 personality answers and
all three substance answers. Missing or malformed data remains backed up but
does not enter the pool. An unrestricted height range is encoded by the app as
absent bounds and means 50–250 cm.

1. Already matched: return the existing match ID, with no new pool entry.
2. Eligible and available: enter the pool; retain the original queue timestamp
   on subsequent profile saves or retries.
3. Evaluate all available candidates, excluding every previous pair.
4. Check requirements and minimum scores in **both** directions.
5. Among qualifying candidates choose the highest exact mean of both directional
   scores. Equal means prefer the longest-waiting candidate, then UUID. Insert
   that match, reserve both user IDs and remove both pool entries atomically.
6. Otherwise retain the user in the pool for the next arrival or profile edit.

A global transaction advisory lock serializes matching, ending, key publication
and message sends. A primary key on the active user reservations independently
prevents double booking. A unique, canonically ordered pair in `matches`
prevents the same two account IDs ever matching again, including after profile
deletion/recreation, off/on toggles, retries, or ending/blocking the match.
This exclusion applies to account IDs; a newly registered account has a new
identity and cannot be linked automatically to a deleted account.

`end_match` retains the record, records who ended it and why, frees both
reservations, and immediately tries to match both participants again if their
saved opt-in is enabled. Turning off auto-matching removes a waiting user;
it leaves an existing conversation active. To stop searching after ending a
match, save auto-matching off before calling `end_match`.

Deleting a profile closes its active match and returns an eligible surviving
partner to the pool. That partner can search immediately with `retry_matching`;
otherwise the next eligible arrival/profile update can find them. Deleting an
Auth account also clears its identity references from history, preserves the
survivor's ended record, and removes the deleted user's key bundles/messages.

## Requirements and scores

Both directions enforce gender, age, height, religion/worldview, at least one
shared language, distance, children/future children, substance frequency limits,
appearance minimum, and the verified-photo preference. The sexual arrangement
selection must overlap as well. The latter and appearance/photo requirements
are additional automatic-matching checks beyond the local exchange report.

The 50 question IDs match `CompatibilityScaleQuestion`. Scores use the local
`MatchReport` formula: weights 0/1/2/4/8 for importance 1–5, linear closeness
over the four-step personality scale and five-step substance scale, including
the inferred substance importance. Each direction must meet that user's own
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
| Read own current state | `rpc("matching_status")` |
| Retry search after reconnect | `rpc("retry_matching")` |
| Read own current/past matches | `from("matches").select()` |
| End/block a match | `rpc("end_match", {p_match_id, p_reason: "closed" or "blocked"})` |
| Publish a device's public bundle | `rpc("publish_match_key_bundle", {p_match_id, p_device_id, p_public_bundle})` |
| Read both participants' bundles | `from("match_key_bundles").select().eq("match_id", matchID)` |
| Store encrypted envelope | `rpc("send_encrypted_message", {p_match_id, p_client_message_id, p_sender_device_id, p_recipient_device_id, p_ciphertext, p_protocol_version: "e2ee-v1"})` |
| Read encrypted history | `from("encrypted_messages").select().eq("match_id", matchID).gt("id", cursor).order("id").limit(100)` |

`matching_status` returns `{state, match_id, photo_verified}`. History contains
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
After attestation call `matching_private.reconcile(userID)` in the same trusted
workflow to search again. A replaced object/version or a different selected photo
does not inherit verification. Do not accept an arbitrary client-supplied flag,
timestamp, or local receipt as a trusted attestation.

## Live chat and E2EE

The real profile home polls the current server match while foregrounded and opens
its live conversation. There is no preloaded mock match in the signed-in root.
Chat sends/receives encrypted messages, retries pending envelopes after network
failure, and synchronizes ending/blocking and reports to the backend. Polling is
foreground-only (3 seconds for chat, 5 for match discovery); push/background
notifications are not implemented.

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

## AWS photo verification

The real automatic-matching photo step now uses the official AWS FaceLiveness
SDK, separate explicit biometric consent and server-confirmed attestation.
The local offline onboarding verification remains local. Existing/current
server photo verification can be restored without repeating a paid AWS scan.
See [AWS activation](aws-photo-verification.md) for the implementation, Ireland
region, server-only credentials, IAM template and remaining account activation.
No trusted verification is fabricated when AWS is unavailable.

## Validation and scaling

Run `supabase/tests/matching.sql` as `postgres` in SQL Editor. It creates isolated
fixtures inside a transaction, switches to `authenticated` for authorization
tests, asserts the lifecycle/score/security rules, then rolls back. On failure
the transaction aborts; run `rollback` if reusing a direct database connection.
The identity sequence may advance, but no fixture rows remain.

Live validation on 14 November 2026: all **54 assertions passed**. A separate
post-rollback check found zero remaining fixture accounts/profiles, zero users
simultaneously waiting and reserved, zero invalid active reservations and zero
matching tables without RLS. The 50 server question IDs were also checked
against the current Swift catalog. Those original checks predate the live chat/AWS changes; additional verification
is recorded with the current implementation.

The initial design serializes writers and scans candidate profiles. It is suited
to validating the first real pool; it has not been load-tested with concurrent
clients. At scale, normalize/index admission/filter fields, reduce candidate
scans, replace the global lock with a proven reservation strategy, add request
rate limits and operational metrics, and test concurrency under load. Retry
transient transaction failures. Avoid adding global workers that silently
recreate history or override users' requirements.

References: [Supabase database functions](https://supabase.com/docs/guides/database/functions)
and [Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
