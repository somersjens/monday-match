# AWS photo verification activation

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

## Account setup still needed

The AWS account was not available when this integration was written. No real
AWS biometric check or paid AWS API request was performed. Finish the AWS signup
and supply account access before activation. Do not paste secret keys into chat
or commit them to this repository.

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

Apply `202611140006_aws_photo_verification.sql` once after migrations 001–005,
then deploy `supabase/functions/aws-face-verification`. `supabase/config.toml`
keeps JWT verification enabled; the function additionally validates the actual
access token with `auth.getUser` and uses the caller's JWT for starting attempts.
All worker/attestation RPCs are denied to anonymous and authenticated clients.
Until the AWS secrets are present, authenticated calls return 503 and no AWS
session is created. Keep the default verified-photo requirement enabled: missing
configuration never silently marks anyone verified.

AWS charges for usage. The per-user quota is a first abuse bound, not a global
spending cap. Set the account's intended cost limit/monitoring before public
activation. This code does not configure billing or subscribe to a paid plan.

## Validate

- `deno check --lock deno.lock index.ts` in the Edge Function directory.
- `deno test policy_test.ts` checks the combined liveness/identity threshold,
  NaN/infinite/out-of-range scores, multiple faces/matches and malformed IDs.
- `supabase/tests/aws_photo_verification.sql` runs all matching/chat regressions
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
