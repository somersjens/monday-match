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

In **all builds, including production**, hold the Lifetime Access card for three
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
