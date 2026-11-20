# Lifetime access

`Get started` moves the existing, continuously running welcome light into a small
header just below the top safe area. The same renderer remains mounted, preserving
its loop phase. The cards appear with staggered lift, blur and opacity transitions;
Reduce Motion uses a short fade instead. Tapping the light or swiping it downward
returns to the landing page. Standalone access routes use the same light header.

Lifetime Access is the first card and the default selection. Explicitly choosing
Early Adopter keeps that choice through store refreshes while it remains available.
The screen uses the onboarding palette and loads both localized prices from
StoreKit, including the struck-through lifetime price. There are no fallback
prices in the application. If products cannot be loaded, retry and restore
remain available; an unpriced purchase cannot proceed.

Configure both App Store Connect products as **non-consumable** purchases:

- `lifetime_access_early_adopter`: free, not family-shareable.
- `lifetime_access`: the desired regional price, not family-shareable.

The client refuses an early-adopter product with a nonzero price, and refuses
consumable or subscription products. Test the live product configuration and
purchase sheet with a Sandbox account/TestFlight before release. For manual local
StoreKit testing, select the fixture under Edit Scheme > Run > Options > StoreKit
Configuration. The test-only
`Stop SwipingTests/LifetimeAccess.storekit` fixture is not selected by the app's
run scheme and does not override live prices.

## Timing and eligibility

The first successful free claim starts the window. The app captures the instant
Continue is tapped before presenting Apple's purchase sheet; restores use the
signed transaction's original purchase date and the earliest recorded start.
Repeated taps, restores, profile resets and restarting the app do not extend it.
An unfinished or cancelled purchase does not unlock the profile questions.
Pending approval is handled by StoreKit transaction updates.

The deadline is `start + 604800` seconds. Completing before that instant records
early-adopter lifetime access. Completion at or after the deadline does not.
The active app checks the deadline, and foregrounding/relaunching rechecks
StoreKit. An expired, unfinished claim shows the picker with only paid access;
profile answers remain saved. Refunds/revocations remove access.

Reminder consent starts off. Turning it on requests iOS notification permission.
A successful free claim schedules one local notification at `start + 518400`
seconds, even when the app is closed. Absolute elapsed seconds avoid daylight
saving and time-zone changes. Disabling it, completing in time, or purchasing
paid lifetime access cancels it. Reopening after its scheduled instant does not
send a late replacement. iOS controls final delivery (for example Focus and
notification summaries); no app can guarantee an exact visible delivery time.
An APNs server is unnecessary for this device-local reminder.

In **debug builds only** (since 20 November 2026; App Store builds have no hidden
features, guideline 2.3.1), hold the Lifetime Access card for three
seconds to reveal the early-adopter option again. Revealing alone does not grant
access. Continuing explicitly starts another seven-day window without a charge;
this exception is persisted in Keychain separately from the original purchase
date and survives relaunching/restoring purchases. Completing within that window
keeps access. Apple's original transaction history is not rewritten. This hidden
reactivation deliberately overrides the normal one-claim restriction.

## Persistence boundaries

StoreKit's verified original non-consumable purchase provides one claim per
Apple purchasing account, including on another device or after reinstalling.
The first claim and timely completion are also kept in a device Keychain record,
separate from local profile storage. Family sharing must remain disabled for the
offers because eligibility is personal.

The existing Firebase integration does not yet provide a trusted entitlement
server or cloud profile-completion restoration. Consequently this implementation
does not establish one claim per physical person across different Apple accounts,
does not defend against manually changing the device clock, and cannot recover a
timely completion on a different device from StoreKit alone. Production enforcement
across app accounts/devices requires a server to verify Apple's signed transactions,
store the first claim by authenticated user and original transaction ID, record
profile completion against server time, and return that entitlement to every device.
Do not use client-writable profile fields as a trusted entitlement ledger.

## Server record (19 November 2026)

Lifetime access is now also recorded per account on the server, so it can
follow the person to another phone or, later, to the Android app.

- After sign-in, and after any purchase, restore or refund, the app sends
  StoreKit's signed transactions (`jwsRepresentation`) to the
  `store-entitlement` edge function (`StoreEntitlementSync`). It sends nothing
  when the set of transactions is unchanged since the last accepted upload.
- The function verifies the signature itself: the x5c chain must end in Apple
  Root CA - G3 (pinned by SHA-256), each certificate must be valid when Apple
  signed, the leaf must carry Apple's receipt-signing OID, and the bundle ID,
  product and type (non-consumable) must match. Local Xcode StoreKit test
  transactions are refused (they aren't signed by Apple).
- `public.store_entitlements` keeps one row per store purchase. The first
  account that records a purchase owns it; another account gets
  `other_account`. Refunds only ever move forward (`revoked_at`).
- `my_store_entitlements()` returns what the signed-in account owns. The iPhone
  still decides access from StoreKit; the Android app will read this.
- Google Play purchases will go into the same table with `store = 'play'`,
  verified with the Play Developer API. Play has no free in-app products, so
  the early-adopter offer needs a promo code or a server-side grant there.

## Plans, accounts and devices (19 November 2026)

There are four App Store products, all recorded per account by the
`store-entitlement` function:

| Product ID | Type | Shown |
| --- | --- | --- |
| `lifetime_access_early_adopter` | non-consumable, free | while the free plan can still be claimed |
| `lifetime_access` | non-consumable | always |
| `monthly_access` | auto-renewable, 1 month, group "Stop Swiping Access" | only once the free plan is gone |
| `lifetime_access_subscriber` | non-consumable, half of `lifetime_access` | home screen, monthly subscribers with auto matching on |

The access screen always shows Lifetime Access, plus exactly one other plan:
the free one while it lasts, the monthly plan after that. Nobody is offered
a monthly fee while they could still have the app for free. The monthly card
carries Apple's subscription terms (auto-renewal, how to cancel, Terms of Use
and Privacy Policy links).

**Who owns access.** Before an account exists, access belongs to the Apple ID
(StoreKit on the device), exactly as before. Once an account exists (Apple or
Google sign-in), every purchase is also recorded on the server for that
account, and the app grants access when *either* says so:

- StoreKit on this device (this Apple ID), or
- `my_store_entitlements()` for the signed-in account: lifetime and subscriber
  lifetime forever unless refunded; the monthly plan while `expires_at` is in
  the future; the free plan with the same seven-day rule, counted from the
  server's purchase date and the profile's completion date.

So someone who bought (or claimed the free plan) on one iPhone can sign in
with Google on another iPhone with another Apple ID, and later on Android,
and keeps access. Signing in waits up to five seconds for the account's
entitlements before the screens decide; they are kept on the phone (cleared
on sign-out and account deletion) so a later launch opens straight away,
also offline. They are read again on every return to the app while they are
the only source of access, otherwise twice a day.

A free plan the account already claimed elsewhere counts as claimed here too,
so a second device can't start a second free week.

**Renewals.** A subscription keeps one original transaction ID, so it is one
row whose `expires_at` moves forward. The app sends each renewal it sees
(the sync fingerprint includes the period end). App Store Server
Notifications V2 post to the same `store-entitlement` URL and update a row
an account already recorded, so a plan bought on an iPhone stays current for
the account's other devices even when that iPhone is never opened.

**Half-price lifetime for subscribers.** A separate non-consumable, because
Apple has no offers for one-time purchases. The card sits above the auto
matching card, as tall as it, while auto matching is on. Closing it hides it
for a calendar month. Apple can't end a subscription for the app (nor can
the server): after the purchase the app asks the person to cancel the
monthly plan and opens the store's own cancel page. While a plan will still
be charged and lifetime access exists, a card with the full sentence
("Now that you have lifetime access, you can cancel your subscription;
otherwise you'll keep paying.") replaces the offer on the home screen,
checked again after the store's page closes and on every return to the app.

Where the plan is billed decides the button (`SubscriptionStore`,
`LifetimePurchasing.manageSubscriptions(in:)`):

| Plan billed to | Known from | Button |
| --- | --- | --- |
| this phone's Apple ID | StoreKit `renewalInfo.willAutoRenew` | Apple's sheet (`AppStore.showManageSubscriptions`) |
| another Apple ID | server `auto_renews` | none: a line says to cancel on that iPhone/iPad |
| Google Play | server `auto_renews` | Google Play's subscriptions page |

The server learns `auto_renews` from Apple's signed renewal info, sent by the
app with its transactions (`appStoreRenewals`) and by App Store Server
Notifications (`signedRenewalInfo`), via `set_store_auto_renew`
(202611190014). Unknown (`null`) never shows the card. On Android the
purchasing layer implements the same two calls with Play Billing:
`monthlyWillRenew` from `Purchase.isAutoRenewing`, and
`manageSubscriptions(in: .googlePlay)` opening
`https://play.google.com/store/account/subscriptions?sku=monthly_access&package=<package>`
(for `.appStore` it shows the "cancel on your iPhone" line); Play's real-time
developer notifications should call `set_store_auto_renew` with `store = 'play'`.

**Known limits.**
- The offer needs an account and the notification step done (the auto
  matching card only shows after both), auto matching on, an active plan, no
  lifetime access, and the `lifetime_access_subscriber` price from the App
  Store. Until that product is approved (it goes to review with an app
  version), the card stays hidden.
- A plan bought on another Apple ID can't be read from this one: the cancel
  card only shows for this Apple ID's own plan (the one-time alert still
  shows).
- Billing grace period is off in App Store Connect. If it's turned on, a
  plan in grace keeps its old `expiresDate`, so the app and server would end
  access early: extend `expiresAt` with `gracePeriodExpirationDate` first.
- The closed offer is remembered per device (UserDefaults); a reinstall
  shows it again.

**Android (later).** Play has no free products. The free plan there needs a
server-side grant (a `store_entitlements` row the server writes when the
account claims it), with the same one-per-account rule; Play purchases and
subscriptions go into the same table with `store = 'play'`. The app already
reads the account's entitlements without caring which store wrote them.
