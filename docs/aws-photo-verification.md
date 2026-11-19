# AWS photo verification activation

> **Status: parked since 18 November 2026.** During the beta the app uses its own
> on-device scan ([photo verification](face-verification.md)), which matches the
> app's look and keeps the camera on the phone, but cannot be proven to the
> server. This AWS version is kept so it can be turned back on.

## Where it is kept

| What | Where |
| --- | --- |
| Complete app at the moment AWS was active | Git tag `aws-liveness-v1` (commit `861516b`) |
| Swift files (flow + consent screen, service, tests) | `archive/aws-face-liveness/` (outside the Xcode targets, so not compiled) |
| Swift package | `https://github.com/aws-amplify/amplify-ui-swift-liveness`, exact version **1.6.0**, product `FaceLiveness`, app target only |
| Edge Function | `supabase/functions/aws-face-verification` (still deployed; unused while parked) |
| Database | Tables/functions in `202611160001_baseline.sql` + `begin_photo_verification` in `202611160004_privacy_consent_v2.sql` (still live, but no longer executable by `authenticated` since `202611190001_abuse_limits.sql`, so the deployed function cannot create paid sessions) |
| AWS infrastructure | `supabase/aws/liveness.yaml`, stack `stop-swiping-face-verification` in eu-west-1; Supabase secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_LIVENESS_STREAM_ROLE_ARN` |
| Localized strings (consent screen, errors) | Still in `Localizable.xcstrings` |

While parked, nothing calls AWS, so there are no Rekognition costs. The IAM
worker key still exists; deactivate it in IAM if it should not stay usable.

## Turning it back on

1. In Xcode: File → Add Package Dependencies → the URL above, *Exact Version*
   1.6.0, product **FaceLiveness** → target *Stop Swiping*. Clean the build folder
   afterwards (see the Smithy plugin note: a stale DerivedData breaks the build).
2. Move the files back:
   `archive/aws-face-liveness/AWSPhotoVerificationFlow.swift` → `Stop Swiping/Features/FaceVerification/`,
   `AWSPhotoVerificationService.swift` → `Stop Swiping/Core/FaceVerification/`,
   `AWSPhotoVerificationTests.swift` → `Stop SwipingTests/`.
3. In `AutoMatchingSetupView`, `WelcomeView` and `DependencyContainer`, swap
   `PhotoVerificationService` → `AWSPhotoVerificationService`,
   `PhotoVerificationState`/`Issue` → `AWSPhotoVerificationState`/`Issue`,
   `.photoVerification(… isPresented:)` → `.awsPhotoVerification(… showsConsent:)`
   and `isSaving` → `isStarting`. `git diff aws-liveness-v1 -- "Stop Swiping/Features/ProfileCreation/AutoMatchingSetupView.swift"`
   shows exactly what changed. In `AdaptiveLayoutRenderTests`, render
   `AWSVerificationConsentView` again as `photo-verification-consent`.
   Optionally delete the on-device scan (Core/FaceVerification + SFace model)
   again to save ~37 MB.
4. Server: stop accepting phone-reported results with
   `revoke execute on function public.record_device_photo_verification(uuid) from authenticated;`
   To make everyone verify again with AWS:
   `delete from matching_private.photo_verifications where method = 'device';`
   Also add `method = 'aws'` to the `on conflict … do update` in
   `complete_photo_verification`, so an AWS result replaces a device one's method.
5. Let the app start AWS checks again:
   `grant execute on function public.begin_photo_verification(uuid, text) to authenticated;`
   and check that it still requires the current privacy consent version (it
   is hard-coded there).
6. Test on a physical iPhone (the simulator cannot run Face Liveness).

The integration uses **Rekognition Face Liveness in eu-west-1 (Ireland)**, the
region supported for Face Liveness within the EU. Supabase's matching data
continues to live in the existing project. No Cognito account migration is needed.

## Flow

1. The app explains that AWS processes the live face video and selected profile
   photo, and asks for explicit consent (`2026-11-14.aws.v1`). A local face scan
   alone cannot create a server attestation.
2. Save the current photo/profile first. The authenticated Edge Function starts
   a database attempt bound to user, selected photo UUID, Storage object ID and
   exact `updated_at`. The database allows five attempts per rolling 24 hours.
3. The backend creates a one-use AWS session. The iPhone receives that session
   ID and 15-minute temporary credentials that allow only streaming a liveness
   check in Ireland. The official Amplify FaceLiveness component streams directly
   to AWS. The application's Apple/Google/Supabase authentication stays intact.
4. After the UI reports completion, the backend independently calls AWS
   `GetFaceLivenessSessionResults`. The client never supplies a confidence,
   matching score, AWS session to attest, or a successful-verification flag.
5. Require AWS status SUCCEEDED and liveness confidence >=95. Download the
   exact selected private profile photo, require exactly one detected face,
   and compare the AWS reference frame with that photo using `CompareFaces`.
   Require one face match with similarity >=95. These are developer thresholds,
   not a guarantee of zero false accepts/rejects; calibrate before public release.
6. The privileged completion RPC checks the user, AWS session, three-minute
   deadline, current selection and object version again. Only then record the
   attestation and retry matching in the same transaction. The second approved
   participant can immediately create a verified-photo-only match.

No S3 output bucket or face collection is used. No audit images are requested.
The app/backend do not persist the live frames, biometric features or AWS
reference image. AWS itself processes the video/images under its service terms;
configure AWS's AI-service opt-out policy before launch if required for your
chosen retention/data-use policy. The database stores consent/version/session
metadata and the verification outcome. No image/video bytes, credentials or
AWS responses are written to application logs.

Profile photo uploads now use immutable UUIDs: if the object already exists,
download and compare its SHA-256 digest. Identical bytes leave the object/version
alone; different bytes require selecting/uploading a new photo ID. This keeps
verification valid after relaunch while preserving invalidation on replacement.

## Account setup and activation status

The AWS account is available. The approved CloudFormation stack
`stop-swiping-face-verification` reached **CREATE_COMPLETE** in Ireland on
15 November 2026. It created the worker user and streaming role defined below.
The role ARN is saved in Supabase as `AWS_LIVENESS_STREAM_ROLE_ARN`.
The account owner created a replacement worker access-key pair and entered it
directly in Supabase Edge Secrets. On 15 November 2026, the dashboard confirmed
the presence of `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and
`AWS_LIVENESS_STREAM_ROLE_ARN`. Only secret names were checked; credential values
were not opened or read by the assistant. Their presence does not validate the
key pair or AWS runtime access. A real-device verification remains to be tested;
no real AWS biometric check or paid Rekognition API request was performed.
Do not paste secret keys into chat or commit them to this repository.

The reviewable infrastructure template is `supabase/aws/liveness.yaml`:

- Deploy in **Ireland / eu-west-1** with the Supabase project ref as parameter.
- The stack needs `CAPABILITY_NAMED_IAM`: it creates one restricted worker user
  and a role for short-lived camera streaming. Review those two policies.
- The worker can create/read liveness sessions, detect/compare faces in Ireland,
  and assume only the camera role. It cannot read unrelated AWS services or S3.
- The camera role trusts only that worker principal with this project's external
  ID. Its session policy further restricts requests to liveness streaming in Ireland.
- The template deliberately does not create or output access keys. Create the
  worker credential yourself and enter it directly into Supabase Edge Secrets.
  For production, replace static worker credentials with your approved workload
  credential rotation/federation strategy when available.

Set these **server-only** Supabase Edge secrets:

| Secret | Value |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Worker access-key ID |
| `AWS_SECRET_ACCESS_KEY` | Worker secret |
| `AWS_LIVENESS_STREAM_ROLE_ARN` | `StreamingRoleArn` CloudFormation output |
| `AWS_SESSION_TOKEN` | Only if the worker itself uses temporary credentials |

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` to the Edge Function. None of the worker credentials
or the Supabase service-role key belongs in `Info.plist`, Swift source, an app
bundle, or a public environment file.

The tables and functions are part of `202611160001_baseline.sql`. Deploy `supabase/functions/aws-face-verification`. The database migration
and function are installed in the live project, and the required AWS secret names
are present. The remaining end-to-end check is a consenting user's verification
on a physical iPhone. `supabase/config.toml`
disables the gateway legacy-secret check for this ECC-token project. The function
authenticates every caller with `auth.getUser` before reading data or calling AWS,
and uses the caller's JWT for starting attempts.
All worker/attestation RPCs are denied to anonymous and authenticated clients.
Until the AWS secrets are present, authenticated calls return 503 and no AWS
session is created. Keep the default verified-photo requirement enabled: missing
configuration never silently marks anyone verified.

AWS charges for usage. The per-user quota is a first abuse bound, not a global
spending cap. Set the account's intended cost limit/monitoring before public
activation. This code does not configure billing or subscribe to a paid plan.

## Validation completed

On 14 November 2026, the live rollback-only SQL suite passed **85 assertions**,
with zero fixture accounts/profiles left behind and RLS on every real matching
table. The current iOS chat/AWS/Supabase run passed **28 tests**; a prior broader
run passed **101**. The Edge Function typecheck and all **3** policy/input tests
passed. Live requests with no session, an invalid session, and only a publishable
key each returned **401 Authentication required**. These checks do not send
photos/videos to AWS.

## Re-run validation

- `deno check --lock deno.lock index.ts` in the Edge Function directory.
- `deno test policy_test.ts` checks the combined liveness/identity threshold,
  NaN/infinite/out-of-range scores, multiple faces/matches and malformed IDs.
- `supabase/tests/matching_regression.sql` runs all matching/chat regressions
  and synthetic trusted-worker tests in one rollback-only transaction. Those
  prove consent, authorization, quota, expiry, session/selection binding,
  idempotence and immediate matching after both photos are approved. They do
  **not** call AWS or prove real biometric performance.
- iOS tests cover the temporary-credential token/expiry, private-key storage,
  encryption/authentication, message replay/tampering and retry behavior.
- After account activation, validate a real consenting person on a physical
  iPhone: cancellation/expiry, photo replacement, success/failure, camera denial,
  network loss, and a wrong-person/photo-spoof attempt. The simulator cannot
  validate real AWS camera/liveness capture.

Sources: [AWS Swift Liveness](https://ui.docs.amplify.aws/swift/connected-components/liveness),
[AWS API flow](https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness-programming-api.html),
[AWS regions/data-use FAQ](https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness-faq.html).
