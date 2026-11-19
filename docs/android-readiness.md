# Ready for Android

Decided 19 November 2026: the Android app will be built later with
[Skip](https://skip.dev) (Swift and SwiftUI compiled for Android), so the
iPhone app stays as it is and the logic is shared. Nothing is ported yet and
there is no Google Play developer account yet.

This page lists what was prepared on 19 November 2026, how to deploy it, and
what is left.

## Prepared

| Area | What changed | Where |
| --- | --- | --- |
| Push for both platforms | Devices have a `platform`; FCM tokens (case-sensitive) are accepted for Android; `push-dispatch` sends APNs and FCM data messages. FCM stays off until `FCM_SERVICE_ACCOUNT` is set. | `supabase/migrations/202611190010_push_platforms.sql`, `supabase/functions/push-dispatch/` |
| No names through Apple or Google | Pushes carry only kind, match, count and the previews switch. The phone adds the name: the new Notification Service Extension on iOS, the data-message handler on Android. | `Core/Notifications/PushPreview.swift`, `Stop Swiping Notifications/`, [notifications](notifications.md) |
| Push entitlement | `aps-environment` was missing from `Account.entitlements` (the file the app is signed with), so no iPhone could get a push token. Added, with the app group for the extension. | `Stop Swiping/Account.entitlements` |
| Lifetime access per account | The app sends Apple's signed transactions after sign-in (and after a purchase or refund, never otherwise); the server checks Apple's signature itself and keeps one record per purchase and account. Android purchases go into the same table (`store = 'play'`). | `202611190011_store_entitlements.sql`, `supabase/functions/store-entitlement/`, `Core/Purchases/StoreEntitlementSync.swift`, [lifetime access](lifetime-access.md) |
| Photo scans proven genuine | Where App Attest is available, the scan report is signed with a Secure Enclave key Apple certified for this app; the server records `attested = true`. Not enforced yet; Android will use Play Integrity. | `202611190012_app_attest.sql`, `supabase/functions/app-attest/`, `Core/FaceVerification/AppAttest.swift`, [photo verification](face-verification.md) |
| Exchange iPhone ↔ Android | Radio-independent channel: handshake, encryption and framing for Bluetooth LE. | `Features/Match/Exchange/ExchangeWire.swift`, [cross-platform exchange](cross-platform-exchange.md) |
| Interop vectors | Bytes both apps must agree on: exchange channel, profile codes, match scores, chat envelope and safety code. | `interop/vectors.json`, `Stop SwipingTests/InteropVectorsTests.swift` |
| Sounds | The palette in Android resource form; the chime as WAV for a notification channel. | `tools/sounds/export_android.sh` → `platform-assets/android/res/raw/` |

## Deploying the server half

**Deployed 19 November 2026** from the SQL editor and the Edge Functions
page (see the deploy notes in [Supabase matching](supabase-matching.md)):

1. Migrations `202611190001_abuse_limits.sql` (was not live yet),
   `202611190010_push_platforms.sql`, `202611190011_store_entitlements.sql`,
   `202611190012_app_attest.sql`. `202611190002` was already live.
2. Live tests, all passing and rolled back: `abuse_limits.sql` (32),
   `push_notifications.sql` (38), `android_readiness.sql` (28).
3. Edge functions: `push-dispatch` redeployed (`index.ts`, `policy.ts`;
   `copy.json` was unchanged); `store-entitlement` and `app-attest` deployed.
   The dashboard code matches the repository files byte for byte (SHA-256).

**Verify JWT with legacy secret** must be off for both new functions (they
check the user themselves, like `apple-revoke`): off for `app-attest`; still
on for `store-entitlement` on 19 November 2026 (by hand). While it is on, the
gateway refuses the app's ECC-signed tokens and the app falls back: purchases
stay on the phone, exactly as before.

Found while deploying: Postgres regexes allow at most 255 repetitions, so the
Android token check (`{32,4096}`) failed on every Android insert. The
migration now checks the length separately; the live constraint was replaced
the same day.

Not checked here: the Deno tests (`policy_test.ts`, `verify_test.ts` in each
function) need Deno, which isn't installed on this Mac; App Attest and the
extension need a real iPhone.

## Left, and what it waits for

| Step | Waits for |
| --- | --- |
| Android package name (e.g. `com.hakketjak.stopswiping`, permanent once on Play) | Your choice |
| `assetlinks.json` next to `apple-app-site-association` in `docs/website/.well-known/`, so code links open the Android app | Package name and the app's signing certificate SHA-256 (Play App Signing) |
| Google sign-in on Android: an **Android** OAuth client in the `stop-swiping` Google Cloud project | Package name and signing SHA-1 |
| Sign in with Apple on Android: a Services ID, return URL `https://yrnwzehdzlxwnhyabwja.supabase.co/auth/v1/callback`, and its client secret in Supabase's Apple provider (expires every 6 months) | Apple Developer portal |
| `apple-revoke` for accounts that signed in with Apple on Android (the code then comes from the web flow, client ID = Services ID) | The Services ID |
| Play Billing products `lifetime_access` and an early-adopter offer. Google Play has no free in-app products: use a promo code or a server-side grant for early adopters | Play account |
| `store-entitlement` for Play: verify the purchase token with the Google Play Developer API (service account) and record `store = 'play'` | Play account |
| Play Integrity next to App Attest in `app-attest`; then enforce attested scans (see the migration's header) | Play account, Android app |
| Bluetooth LE transport for the exchange, on both platforms | Two test phones |
| FCM: Firebase project for the Android app, `FCM_SERVICE_ACCOUNT` secret | Android app |
| Privacy policy: Google (FCM, Play) as processors; Bluetooth for the exchange | Before the Android release; check the consent version rule |
| Metal welcome light, Vision + SFace scan, StoreKit, MultipeerConnectivity: Android versions (Compose/OpenGL, ML Kit + SFace ONNX, Play Billing, BLE) | The Skip port |
