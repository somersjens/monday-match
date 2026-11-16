# Notifications

How Stop Swiping decides what to tell people, when, and in which voice. The
goal: make people smile and tap, without making them want to mute the app.

## 1. Audit: what the app actually has (16 November 2026)

| Area | What exists | What it means for notifications |
| --- | --- | --- |
| Automatic matching | Server-owned, in Postgres. A profile sync admits the user; a match is created atomically in `public.matches`. One active match at a time. `break_match`, reports and moderation end matches (`ended_at`, `ended_by`, `end_reason`). | "New match", "first match" and "match ended" are real server events. A match means both people meet each other's requirements and minimum scores. It does **not** mean anyone has seen or liked anyone, so copy never says "someone likes you". |
| Matching preferences | `AutoMatchingSettings`: on/off, `minimumMatchPercent` (50–90, step 5), appearance scores, verified-photo requirement. `hasCompletedSetup` with missing appearance scores = paused setup (the appearance-scale migration does this). | "Lower your standards" uses `minimumMatchPercent ≥ 85`. "Preferences need attention" uses `hasCompletedSetup && !isReady`. When auto-matching was switched on is not stored anywhere, so the notification system records it locally. |
| Messaging | One conversation per match, end-to-end encrypted on the devices (HPKE). The server stores opaque envelopes, read positions (`match_read_states`) and timestamps only. Polling is foreground-only (3 s chat, 5 s match). | The server can never put message text in a push. It knows the sender and that a message exists. Real previews would need a Notification Service Extension that decrypts on the device (see §6). |
| Compatibility checks | The in-person profile exchange: two phones held together (MultipeerConnectivity/NearbyInteraction) or a QR code, entirely offline. The result shows instantly. `hasUsedProfileExchange` is stored; saved results go to `SavedMatchStore`. | "Asked a coworker to check compatibility" = completed an exchange or scanned a code. There are **no** compatibility requests, responses, pending results or expiry dates: the check is synchronous and in person. |
| Privacy | Two consents with versioned receipts: profile (`PrivacyConsentKind.profile`) and matching. Version `2026-11-15.v2`. Profile sharing needs the current profile receipt; the server admits nobody to matching without both current receipts. | "Consent required" and "updated terms" are both detectable from the receipts. Copy must be accurate: without consent nothing is shared and matching is paused. |
| Onboarding | `ProfileCreationState`: `currentStep`, `furthestStep`, `progress`, `completedAt`, `isUnderageLocked`. The app reopens the questionnaire where it stopped. | "Incomplete onboarding" is supported; the app already resumes at the right step. |
| Moderation | Strikes, 7-day blocks, bans; shown in the app as an alert. | Matching is unavailable while suspended or banned, so matching nudges are suppressed. Moderation itself is never pushed (it is sensitive and already shown in the app). |
| Notification infrastructure | `UNUserNotificationCenter` local notifications (`EarlyAccessReminder`), a permission step in onboarding (`NotificationPermissionService`), the `notification-chime.caf` sound, the `remote-notification` background mode and an `aps-environment` entitlement. No device-token registration, no push sender, no preferences. | Built on: local notifications for everything the phone can decide, plus a small Supabase push pipeline for the three events that happen while the app is closed. |

## 2. Architecture

```
                      ┌────────────────────────── iPhone ───────────────────────────┐
 profile, consent,    │  NotificationContext ──► NotificationPlanner (pure) ──► plan │
 live match, signals ─┤        ▲                       ▲                        │    │
                      │  NotificationSignalStore  NotificationLedger      NotificationEngine
                      │  (activity, exchange,     (history, dedupe,       ├ syncs pending UN requests
                      │   auto-match since)        analytics, A/B)        ├ in-app banners
                      │                                                   ├ deep links
                      │                                                   └ push token ─┐
                      └───────────────────────────────────────────────────────────────│─┘
                                                                                      ▼
 matches / encrypted_messages / match_read_states ─► triggers ─► notification_private.outbox
                                                                     │ (coalesced per thread)
                                       pg_cron (15 s) ─► push-dispatch edge function ─► APNs
```

* **One planner, one place for rules.** Every local notification comes out of
  `NotificationPlanner.plan(context:ledger:preferences:now:)`, a pure function.
  It knows every kind, its eligibility, timing, priority, cooldown and budget.
  It is replanned on launch, on every return to the foreground, when the app
  goes to the background, and whenever the profile or the live match changes.
* **Automatic cancellation.** Each planned notification has a stable identifier
  derived from its dedupe key. Syncing removes every pending request that is no
  longer in the plan. Finishing an action, a new message, a broken match or a
  consent change therefore cancels the stale reminder at the next replan.
* **Server push only for what the phone cannot know**: a new match, new
  messages and a match ending, while the app is closed. Coalescing happens in
  Postgres, so a burst of messages becomes one push.

## 3. Notification matrix

Times are the user's local time. "Nudge" = reminder or engagement; nudges share
a budget of **2 per rolling 7 days**, at least **36 h apart**, never sooner
than **24 h after the user was last active**, and never during quiet hours
(**22:00–09:00**, configurable). Transactional notifications are not budgeted;
during quiet hours they arrive silently (`passive`). Every kind fires at most
once per dedupe key.

**The voice fits how this app works.** Nobody here swipes, browses or likes
anyone. A match means two people meet each other's requirements and minimum
scores, based on their answers; a compatibility check is two phones held
together or a scanned code. So copy talks about answers, compatibility, phones
and codes, and never claims that someone liked, chose, wants or is waiting
for the user. `NotificationCopyTests` rejects any line that does.

**Two languages, written separately.** Every notification exists in English
and Dutch, in the app's current language. The Dutch lines are not
translations: they use informal "je", the app's own terms ("Automatisch
matchen", "Mijn matches") and Dutch jokes ("Nul keer geswipet, één match",
"Ghosten is zó vorig seizoen", "Dit gesprek moet gereanimeerd worden"). The
matrix below shows English; the Dutch set has the same slots and the same
number of lines. Switching the app's language rewrites what is pending, and
the phone tells the server its language for pushes.

**Variety follows frequency.** The table shows a few lines per notification;
the full catalog is in `NotificationCopy.swift`: 8 lines for a new match,
4 per message flavour, 5 for match ended, quiet and unanswered conversations,
no first hello and the monthly check, 4 for rarer nudges, and 2 for consent
and errors, where clarity matters more than surprise.

| # | Event | Conditions | Timing | Title | Body | Deep link | Priority | Cooldown |
|---|---|---|---|---|---|---|---|---|
| 1 | New auto-match (push, server) | Match created; transactional on | Immediately | Well, well, well… | Someone's a match. Go say hi before you overthink it. | `match` | 2 – transactional | Once per match |
| | | | | It's a match | The algorithm did the hard part. The hello is on you. | | | |
| | | | | Plot twist: a match | Your compatibility checks out with someone. Go see who. | | | |
| | | | | Zero swipes, one match | All those questions paid off. Go see who it is. | | | |
| | | | | Compatible. Both ways. | You tick their boxes, they tick yours. The rest is up to you two. | | | |
| | | | | Match found. No swiping involved. | Your answers did the talking. Now it's your turn. | | | |
| 1b | First match ever (push, server) | As 1, and the user's first match | Immediately | Your first match. Finally. | Worth the wait. Go see who it is. | `match` | 2 | Once |
| | | | | First match unlocked | Mark the date. Now go make it a story. | | | |
| 2 | New message (push, server) | Partner message; transactional on; not read within the batching window | 15 s after the last message of a burst, at most 2 min after the first; then at most one push per thread per 3 min, replacing the previous one (`apns-collapse-id`) | Previews on: `{match_name}` | `{match_name}` sent you a message. / … has something to say. / sent `{count}` messages. Somebody's chatty. | `chat` | 2 | 3 min per thread |
| | | Previews off | | New message | Open the app to read it. / `{count}` new messages are waiting. | | | |
| 3 | Match ended | Ended by the partner, a deletion or moderation, not by this user; not shown to a suspended user | In-app banner when next open. Push only with "Match ended alerts" on (default **off**): silent background push otherwise | Well, that chapter was short. | This match has ended. The conversation stays readable in My matches. | `myMatches` | 2 | Once per match |
| | | | | And… scene. | This match is over. No drama, just a fresh start. | | | |
| | | | | Onward. | Your match has ended. Plenty of plot left. | | | |
| 4 | Conversation going quiet | Active match; both have written; nothing unread; idle ≥ 4 days (configurable) and the last message is the partner's, or idle ≥ 8 days | Idle threshold reached, then shifted out of quiet hours | This conversation needs CPR | One message could bring it back. | `chat` | 4 – reminder | Once per quiet stretch (keyed on last message) |
| | | | | Awkward silence detected | Someone has to break it. Might as well be you. | | | |
| | | | | Don't let it fizzle | Good conversations don't text themselves. | | | |
| 5 | Message unanswered | Partner message unread (chat not opened since) | 20 h after the oldest unread message | Playing hard to get? | Or just forgetful? You have a message waiting. | `chat` | 3 – pending interaction | Once per unread message |
| | | | | Left on unread | Rude, but fixable. Your match wrote to you. | | | |
| | | | | Fashionably late | Any later and it's just late. Your reply is waiting. | | | |
| 5b | Match, no conversation yet | Active match, no messages from either side | 24 h after the match | Cupid has done his part | Your move. A simple hi has worked for centuries. | `chat` | 3 | Once per match |
| | | | | Someone has to go first | Be the brave one. Say hi to your match. | | | |
| | | | | Silence isn't mysterious | It's just silence. Say hi to your match. | | | |
| 6 | Privacy approval required | Profile finished and named; profile consent never given | 24 h after it is first noticed, again 4 days later, then never | Even Cupid needs your consent | Accept the privacy terms to share your profile and use matching. Nothing is shared until you do. | `privacy` | 1 – account | 2 sends total |
| | | | | One signature away | Profile sharing and matching need your privacy consent first. Read it, then decide. | | | |
| 7 | Updated privacy terms | A receipt exists but is for an older version | 12 h after first noticed, again 5 days later, then never | We've updated our privacy terms | Please review them. Profile sharing and matching are paused until you accept. *(matching only: "Auto-matching is paused until you accept.")* | `privacy` or `autoMatching` | 1 | 2 sends per version |
| | | | | Plot twist: new privacy terms | Review what changed. Sharing and matching resume once you accept. | | | |
| 8 | First matchmaking reminder | 7 days after accepting the profile terms; never exchanged a profile or scanned a code; matching available | Acceptance + 7 days | That coworker isn't going to check themselves | Hold your phones together and see if you're compatible. It takes seconds. | `share` | 4 | Once |
| | | | | Curious about someone? | Phones together, results in seconds. No awkward questions required. | | | |
| | | | | All dressed up | Your profile is ready and going nowhere. Check your compatibility with someone. | | | |
| 9 | Consider lowering your standards | Minimum match ≥ 85 %; auto-matching on ≥ 30 days; no match since it was switched on; no active match | 30, 60, 90… days after switching on | Your standards are giving "unattainable" | A month without a match. Your matching preferences might be why. | `autoMatching` | 5 – engagement | Once per 30-day period |
| | | | | High standards. Low results. | Coincidence? Take a look at your matching preferences. | | | |
| | | | | Picky is a strategy | So far, a lonely one. Review your minimum match score. | | | |
| 10 | No compatibility check for a month | A check happened before; none in 30 days; matching available; no active match | Last check + 30 days | Your love life called | It's bored. Check your compatibility with someone new. | `share` | 4 | Once per last check |
| | | | | Another month, another missed opportunity | Hold your phones together with someone. It takes seconds. | | | |
| | | | | It's been a month | Your profile misses being compared. Find someone and check. | | | |
| 11 | Auto-matching on, user away | Auto-matching on; no active match; app not opened for 14 days; standards nudge not sent in the last 14 days and not due | Last active + 14 days | Cupid is working overtime. You? | Auto-matching is still on the job. Drop by sometime. | `profile` | 5 | Once per absence |
| | | | | Still looking | Auto-matching keeps searching while you're away. You'll hear from us when there's a match. | | | |
| 12 | Incomplete onboarding | Questionnaire started, not finished, not age-locked; no early-access deadline reminder within 48 h | 24 h after last activity, again 4 days later | You left us on read. Already? | Your profile is `{percent}`% done. Pick up where you left off. | `onboarding` | 4 | 2 sends per absence |
| | | | | Halfway there is nowhere | A few more questions and you're in. | | | |
| | | | | Your profile is ghosting us | Finish it and let the matching begin. | | | |
| A1 | Matching preferences need attention | Auto-matching set up before, scores now missing (paused) | 24 h after first noticed | Auto-matching is on a break | A couple of preferences are missing. Fill them in to resume. | `autoMatching` | 1 – account | Once |
| | | | | Your preferences need a refresh | Auto-matching is paused until you finish them. Two quick taps. | | | |
| A2 | Message not sent | Encrypted messages still queued when the app leaves the foreground | 15 min after leaving | Your message didn't make it | Open the app to send it. It's waiting, encrypted and ready. | `chat` | 2 | Once per queue |
| | | | | Stuck in the outbox | A message hasn't been sent yet. Open the app to retry. | | | |
| A3 | Welcome back (in-app only) | App opened after ≥ 30 days away | On open | Look who's back. | Your profile is right where you left it. | — | in-app | 30 days |

### Additional scenarios not built, and why

| Scenario | Status |
| --- | --- |
| Compatibility check requested / responded / about to expire | **Unsupported.** Checks are in-person and instant; there is no request object, no response and no expiry. Would need a remote "invite to compare" feature first. |
| Compatibility result ready | **Unsupported / unnecessary.** The result shows on both phones the moment the exchange completes. |
| Auto-matching paused / reactivated / disabled | Partly covered: paused by outdated consent (#7) or missing preferences (A1). Switching it off or on is the user's own action, so it is not notified. Suspension is shown in the app's existing moderation alert, never pushed. |
| Recoverable error | Covered where it helps: unsent messages (A2). Profile sync failures already show on the home screen with a retry; a push would not fix them. |
| Real message text in pushes | **Optional, needs a Notification Service Extension** that shares the chat keys through a Keychain access group and decrypts on the device. Server pushes already set `mutable-content`, so the extension can be added later without server changes. |

## 4. Flow

### Eligibility (in this order)

1. **System permission.** Not authorized → nothing is scheduled; in-app banners
   still work. Losing permission (authorized → denied) is recorded as an
   opt-out and the device is unregistered from push.
2. **Preferences.** Matches & messages (transactional), Tips & nudges
   (reminders and engagement), Match ended alerts, Message previews, quiet
   hours. Account notifications (consent, paused matching) ignore the
   nudges switch because they are about required actions, but still respect
   quiet hours.
3. **Account state.** No account → only onboarding and consent notifications.
   Required consent missing or outdated → every matching nudge is suppressed
   and the consent notification takes their place.
4. **Matching availability.** Matching and compatibility nudges require a
   shareable profile, no suspension or ban, and (for compatibility) no active
   match: with a match, you're matched with that one person only.
5. **Completed actions.** Each condition is re-evaluated at every replan; a
   finished action simply stops producing the candidate, and the sync cancels it.
6. **Dedupe and cooldown.** The ledger keeps every delivered dedupe key; a key
   never fires twice. Per-kind cooldowns apply on top.
7. **Budget.** Nudges are placed in priority order into the rolling 7-day
   budget; lower-priority ones wait or drop.

### Timing

* Fire time = max(trigger time, now + 1 min, last activity + 24 h for nudges).
* Inside quiet hours → next quiet-hours end, plus a stable 0–45 min offset per
  notification so pushes don't all land at 09:00 sharp.
* Local notifications use a floating `UNCalendarNotificationTrigger` (no time
  zone), so a trip abroad still delivers at local wall-clock time.
* The server computes quiet hours from the time zone the phone registered.

### Cancellation

| Change | Effect |
| --- | --- |
| Chat opened or answered | Unanswered and quiet reminders for that conversation disappear from the plan; server deletes pending message pushes up to the read position. |
| Match ends | All conversation reminders cancelled; server deletes pending pushes for that match. |
| Consent accepted | Consent reminders cancelled; matching nudges become eligible again. |
| Consent withdrawn (profile restart) | Matching nudges cancelled; consent reminder planned. |
| Exchange completed | First-matchmaking reminder cancelled; monthly check restarts its 30 days. |
| Auto-matching switched off | Standards and away nudges cancelled; their "since" date resets. |
| Profile deleted or signed out | Everything pending is removed, local history cleared (deletion), device unregistered. |

### Priority

1 required privacy/account actions → 2 messages and matches → 3 pending
interactions (unanswered, first hello) → 4 useful reminders → 5 playful
nudges. Priority decides who gets the weekly budget and which notification is
kept when two would land together.

### Edge cases

* **App open when a match arrives:** the app shows the match itself; the engine
  marks it handled so nothing is sent afterwards. A server push that arrives
  while the app is in front is not shown as a banner for the open chat.
* **Rapid conversations:** coalesced to one push per thread per 3 minutes; the
  newer push replaces the older one on the lock screen with the latest count.
  Reading the chat before the push goes out cancels it.
* **Breaking your own match:** no "match ended" notice: you know.
* **Moderation endings:** a suspended or banned user gets the moderation alert,
  not a cheerful "onward".
* **Reinstall / new phone:** the ledger is local; the planner still waits 24 h
  after activity, so a fresh install never gets a burst of old reminders.
* **Same phone, new account:** registering a token moves it to the new account
  on the server; the old account stops receiving pushes on that phone.
* **Clock or time zone changes:** replans on every foreground; floating
  triggers follow the new zone.
* **iOS limit of 64 pending requests:** the plan holds at most a handful.

### Privacy on the lock screen

* Names appear only in message notifications, and only with previews on.
* No reminder mentions a score, a name, a coworker, a reason or who ended
  anything. Copy says "a match" and "someone", never "likes".
* Message text never reaches the server; even with previews on, a server push
  says "sent you a message".
* Consent copy says exactly what is paused and that nothing is shared until
  the user accepts.

## 5. Implementation map

| Piece | File |
| --- | --- |
| Kinds, categories, priorities, cooldowns | `Core/Notifications/NotificationKind.swift` |
| Copy catalog, placeholders, variants, A/B buckets | `Core/Notifications/NotificationCopy.swift` |
| Tunables (quiet hours, budget, delays) | `Core/Notifications/NotificationPolicy.swift` |
| Preferences | `Core/Notifications/NotificationPreferences.swift` |
| Planner input | `Core/Notifications/NotificationContext.swift` |
| History, dedupe, analytics | `Core/Notifications/NotificationLedger.swift` |
| Rules | `Core/Notifications/NotificationPlanner.swift` |
| Deep links | `Core/Notifications/NotificationDestination.swift` |
| Orchestration, UN sync, delegate, push token | `Core/Notifications/NotificationEngine.swift`, `PushDeviceRegistration.swift` |
| Settings screen and in-app banner | `Features/Notifications/` |
| Server tables, coalescing, RPCs | `supabase/migrations/202611160002_push_notifications.sql` |
| APNs sender | `supabase/functions/push-dispatch/` |
| Tests | `Stop SwipingTests/NotificationPlannerTests.swift`, `NotificationEngineTests.swift`, `supabase/tests/push_notifications.sql` |

Copy for the three server-sent kinds lives in
`supabase/functions/push-dispatch/copy.json`; `NotificationCopyTests` fails if
it drifts from the app's catalog.

### A/B testing

Each install gets a stable bucket per kind (FNV-1a of an install ID and the
kind). The first variant shown is the bucket's; later sends rotate from there,
so nobody sees the same line twice in a row. Every delivery, open, action and
dismissal is recorded with its variant ID in the ledger, which
`NotificationLedger.variantSummary()` turns into opens per variant. Nothing
leaves the phone; wire the summary to an analytics service if one is added.

## 6. Deploying the server half

Nothing here is live yet. In order:

1. Create an APNs auth key (Apple Developer → Keys → Apple Push Notifications
   service). Add Supabase function secrets `APNS_KEY_ID`, `APNS_PRIVATE_KEY`
   (the .p8 contents) and `PUSH_DISPATCH_SECRET` (a long random string).
   `APPLE_TEAM_ID` is already set for `apple-revoke`.
2. Run `supabase/migrations/202611160002_push_notifications.sql` in the SQL
   Editor (it runs after the baseline; never rerun the baseline).
3. Run `supabase/tests/push_notifications.sql` ("Run without RLS"; it rolls back).
4. Deploy `supabase/functions/push-dispatch` (with `policy.ts` and
   `copy.json`). "Verify JWT with legacy secret" must be off; the function
   checks `PUSH_DISPATCH_SECRET` itself.
5. Enable `pg_cron` and `pg_net`, store the secret in Vault, and schedule:

   ```sql
   select vault.create_secret('<PUSH_DISPATCH_SECRET>', 'push_dispatch_secret');
   select cron.schedule('push-dispatch', '15 seconds', $$
     select net.http_post(
       url := 'https://yrnwzehdzlxwnhyabwja.supabase.co/functions/v1/push-dispatch',
       headers := jsonb_build_object('Content-Type', 'application/json',
         'X-Dispatch-Secret', (select decrypted_secret from vault.decrypted_secrets where name = 'push_dispatch_secret')),
       body := '{}'::jsonb, timeout_milliseconds := 10000);
   $$);
   ```
6. Switch `aps-environment` to `production` for App Store builds (the app sends
   `sandbox` from debug builds and `production` otherwise).

Until then the app's local notifications work on their own; new matches and
messages are noticed when the app is opened, as before.
