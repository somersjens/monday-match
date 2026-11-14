# Stop Swiping

Open `Stop Swiping.xcodeproj` in this folder. This is the single active project.

The app and Xcode targets are named **Stop Swiping**. The existing App Store SKU
and bundle identifiers are unchanged so the app keeps its existing identity.

- `Stop Swiping/`: SwiftUI app source and assets.
- `Stop SwipingTests/`: unit and Metal rendering tests.
- `Stop SwipingUITests/`: UI tests.
- `supabase/`: database and private Storage migration.
- `exports/`: reference artwork.
- `2 circle.mp4`: animation reference, kept locally and not played by the app.

The project includes profile creation, the heart/lock/helix/QR animations, and
the latest welcome entrance and dark startup fixes.

## Supabase integration

The app uses the official `supabase-swift` package for Sign in with Apple and Google,
Keychain-backed sessions, Postgres profile backups and private photo storage.
Firebase is no longer an app dependency.

- The project URL and client-safe publishable key are in `Stop Swiping/Info.plist`.
  Never put a Supabase secret/service-role key in the iOS app.
- `SupabaseAuthService` exchanges the Apple ID token and the original nonce
  for a Supabase session. Apple's request receives the SHA-256 nonce.
- Google sign-in uses the system authentication browser and Supabase's PKCE
  authorization-code flow. Both providers share the profile backup and restore
  step before progressing to notifications. Cancelling either provider returns
  to the account screen without an error; concurrent sign-ins are disabled.
- `SupabaseProfileSync` uploads the completed, consented local profile after
  account creation and after saved edits. A returning account restores its
  existing backup; an offline device retains its local answers for retry.
- Photos are uploaded to the private `profile-photos` bucket in display order,
  under `<auth-user-id>/<photo-id>.jpg`. Stored references require authentication.
  Photo bytes are excluded from the database JSON, and precise coordinates are
  rounded before any profile backup leaves the device. Live face-scan data and
  verification receipts are not included in the backup.
- Row Level Security restricts both profiles and photos to their owner. The
  publishable key alone cannot read profiles or download private photos.
- The account switch opens the Apple/Google sign-in options. Only successful authentication and
  initial profile backup unlock the notification step and automatic matching.

Database and bucket setup is recorded in
`supabase/migrations/202611140001_profiles.sql`. Apple native sign-in uses the
bundle ID `Hakketjak.monday-match`; enable that client ID in the project's Apple
provider and the Sign in with Apple capability for the Apple App ID. Native
ID-token sign-in does not require a web OAuth secret.

For Google, configure a **Web application** OAuth client in Google Cloud with
the authorized redirect URI
`https://yrnwzehdzlxwnhyabwja.supabase.co/auth/v1/callback`.
Store its client ID and secret only in Supabase's Google provider settings,
then enable that provider. Add `stopswiping://auth/callback` to Supabase's
allowed Redirect URLs; the matching iOS URL scheme is in `Info.plist`.
The Google Cloud project is `stop-swiping`, with the OAuth client named
`Stop Swiping – Supabase`. The Google provider and the exact app redirect are
configured in Supabase. The OAuth app currently has Google's **Testing**
publishing status, with one approved test account. Its future branding links are
`https://hakketjak.com/stop-swiping#en` and
`https://hakketjak.com/stop-swiping/privacy#en`. These pages are not live yet;
keep Google in Testing until the pages are available and public release is requested.
OAuth client secrets are stored in Supabase, never in the iOS app or source control.

Profile sync errors remain visible on the profile home with a retry action.
Mock authentication is available only when explicitly injected in previews or
tests. Missing Supabase configuration fails account creation instead of
pretending that an account was created.

Automatic matching now runs in Postgres on every profile save: opted-in eligible
users join the pool, mutually compatible users are reserved atomically, and
past pairs are permanently excluded for the same account IDs. The two matching
migrations and the rollback-only SQL tests are in `supabase/`.
See [matching backend](docs/supabase-matching.md) for the lifecycle, API contract,
admin overview, verification requirements and deployment notes. The real profile home now
opens live encrypted chat, with CryptoKit HPKE, Keychain device keys, security
codes, retry handling, blocking and reporting. AWS Face Liveness integration for
verified profile photos is implemented; see [AWS activation](docs/aws-photo-verification.md)
for the account/secret setup that remains before real verification can run.

Reference: [Supabase SwiftUI setup](https://supabase.com/docs/guides/getting-started/quickstarts/ios-swiftui),
[Apple sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple),
[Google sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-google),
[Storage access control](https://supabase.com/docs/guides/storage/security/access-control).

## Profile exchange and match scores

Two people who both tap **Share profile** and hold their phones together
exchange profiles directly, without an account or internet
(`Features/Match/Exchange`):

- Phones find each other with MultipeerConnectivity (encrypted) and measure
  the distance with NearbyInteraction (ultra wideband). Held together, both
  say they are ready; a profile is only sent once both have. Tapping
  **Exchange** on both phones does the same where distance can't be measured.
- What leaves the phone is `ProfileCreationState.sharedCopy`: the answers,
  the age (not the birthday), a location rounded to about a kilometre, and
  no auto-matching data. Received profiles are validated before use.
- Needs `NSLocalNetworkUsageDescription`, `NSBonjourServices` and
  `NSNearbyInteractionUsageDescription` (in `Info.plist`). The distance
  trigger (`ProximityGate`, 15 cm) still has to be tuned on real devices.

The QR code on the same screen is the fallback when the phones don't find
each other. It works one way: whoever scans it sees the match.

- `ProfileCode` packs the same shared copy into about 100 bytes of bits and
  puts it behind the `#` of `https://www.hakketjak.com/stop-swiping/code`.
  The answers travel in the code itself and never reach a server: a browser
  doesn't send that part of a link. The bit layout is a format; its tables
  are only ever appended to, and `formatVersion` changes with anything else.
- The link is a universal link (`applinks:www.hakketjak.com` in
  `Account.entitlements`). With the app installed, the iPhone's Camera opens
  the app directly; without it, the page opens and leads to the App Store.
  The site's files are in `docs/website`: copy `.nojekyll`, `.well-known/`
  and `stop-swiping/code.html` to the root of the Hakketjak-Website
  repository. Until they are live, a code scanned with the Camera app opens
  a missing page; scanning inside the app always works.
- Scanning in the app is `ProfileCodeScannerView`, the camera button beside
  the code. Links arrive in `ProfileCodeInbox`, which holds the profile
  until the home screen can show the match and says so when this phone's own
  profile isn't finished yet. The older `stopswiping://code/…` form is still
  read; the page uses it for people whose phone didn't open the app.
- `ProfileCodeTests` renders the code of light and reads it back; scanning
  from a real screen with a real camera still has to be tried on devices.

Scores (`MatchReport`) are a weighted average of how close each answer is to
what was looked for. Importance 1-5 weighs 0, 1, 2, 4, 8. Alcohol, smoking
and drugs count too: the closer to the seeker's own use the better, with an
importance derived from how strict their limit is. A match is possible as
long as every requirement is met both ways, including being at or under each
limit.

## Photo verification

Local front-camera photo verification and upload guidelines are integrated into
both photo inputs. See [face verification](docs/face-verification.md) for model
provenance, configuration, privacy behavior and device-validation requirements.
