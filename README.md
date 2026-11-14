# Stop Swiping

Open `Stop Swiping.xcodeproj` in this folder. This is the single active project.

The app and Xcode targets are named **Stop Swiping**. The existing App Store SKU
and bundle identifiers are unchanged so the app keeps its existing identity.

- `Stop Swiping/`: SwiftUI app source and assets.
- `Stop SwipingTests/`: unit and Metal rendering tests.
- `Stop SwipingUITests/`: UI tests.
- `firebase/`: starter backend rules.
- `exports/`: reference artwork.
- `2 circle.mp4`: animation reference, kept locally and not played by the app.

The project includes profile creation, the heart/lock/helix/QR animations, and
the latest welcome entrance and dark startup fixes.

## Firebase integration

This block introduces a conditional Firebase integration while preserving the
Firebase-free mock build.

## Added

- Firebase bootstrap
- Conditional dependency selection
- Sign in with Apple button
- Cryptographically secure nonce generation
- SHA-256 nonce hashing
- Firebase Apple credential exchange
- Firebase session restoration and sign-out
- Cloud profile DTO
- Firestore profile repository
- Firebase Storage photo uploader
- Starter Firestore rules
- Starter Storage rules

## Firebase installation

In Xcode:

1. Open `File > Add Package Dependencies`.
2. Add:

   `https://github.com/firebase/firebase-ios-sdk`

3. Select:

   - `FirebaseAuth`
   - `FirebaseFirestore`
   - `FirebaseStorage`

4. Download `GoogleService-Info.plist` from the Firebase console.
5. Add it to the Xcode project and the main app target.
6. In Firebase Authentication, enable the Apple provider.
7. In the Apple Developer portal and Xcode target, enable the
   `Sign in with Apple` capability.
8. Create Cloud Firestore and Cloud Storage.
9. Deploy the starter rules from the `firebase` directory.

Firebase recommends Swift Package Manager for Apple-platform projects. The app
calls `FirebaseApp.configure()` only when `FirebaseCore` is available.

## Conditional compilation

Before Firebase is installed:

- `MockAuthService` is used.
- The real Apple authorization sheet still opens.
- The returned Apple token is accepted by the mock service.
- Existing local MVP features remain available.

After Firebase is installed:

- `FirebaseAppleAuthService` is selected automatically.
- Apple ID tokens are exchanged for Firebase credentials.
- Existing Firebase sessions are restored.
- Sign-out calls Firebase Authentication.

## Apple nonce flow

Every request:

1. Generates a random nonce with `SecRandomCopyBytes`.
2. Sends the SHA-256 hash to Apple.
3. Keeps the raw nonce temporarily.
4. Passes Apple’s ID token and the raw nonce to Firebase.

This protects the sign-in exchange against replay attacks.

## Cloud profile shape

`CloudProfile` intentionally stores:

- profile text and preferences
- compatibility answers
- photo download URLs
- rounded coordinates
- radius and completion state
- update timestamp

It does not expose exact coordinates in the cloud DTO.

## Photo upload path

Photos upload as JPEG to:

`users/{uid}/profilePhotos/{photoID}.jpg`

The uploader returns download URLs in display order.

## Important limitations

- Onboarding completion is not yet uploaded automatically.
- Firestore does not yet decide whether a returning user still needs onboarding.
- Chat is not connected to Firestore.
- Backend matching does not exist yet.
- Starter rules require a full security review before production.
- Public read access to profile photos may need a different authenticated design
  depending on how matched profiles are delivered.

## Next block

The next build block can connect onboarding completion to Firebase:

- upload photos
- write `CloudProfile`
- show upload progress
- retry failed uploads
- restore a cloud profile
- decide onboarding versus dashboard from Firestore
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
