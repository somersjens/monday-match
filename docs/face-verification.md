# Local photo verification

> **19 November 2026:** where the iPhone supports App Attest, the scan report
> is signed with a Secure Enclave key that Apple certified for this app, and
> the server records it as `attested` (`app-attest` edge function,
> `202611190012_app_attest.sql`). Unsupported devices, the simulator, and the
> time before the function is deployed fall back to the unproven route. The
> migration's header says how to require proof once Android (Play Integrity)
> does the same.
>
> **Status (18 November 2026):** this on-device scan is the app's photo
> verification again during the beta. It was removed on 16 November in favour of
> AWS Face Liveness and restored from Git (`feb4c9e^`). AWS is parked; see
> [AWS photo verification](aws-photo-verification.md).
>
> The auto-matching photo step opens the scan from its **Verify this photo**
> button through `PhotoVerificationFlow`, with no screen in between. After a
> **Match**, `PhotoVerificationService` uploads the profile/photo and calls
> `record_device_photo_verification`, so the server records that photo version
> as verified and matching treats it like an AWS result. Only the photo ID is
> sent; frames and face features still never leave the phone. The server takes
> the app's word for the scan. Notes below about receipts being local-only and
> not a server credential describe the scan itself; the server record is what
> matching uses.

The selected auto-matching photo is the reference. No second reference upload
is introduced.

The camera only starts after the user taps **Verify this photo** and grants
camera permission. AVFoundation supplies HD, upright, unmirrored front-camera
frames on a private serial queue. Motion feedback runs at up to twelve analyses
per second; initial/final identity comparisons run at roughly six. The auxiliary
capture-quality request is skipped during the circle, where it is not used.
Capture and preview each use `AVCaptureDevice.RotationCoordinator` for the actual
camera; a fixed 90-degree rotation is incorrect on some newer front sensors.
Coordinator angles are snapped to quadrants so hand tremor does not repeatedly
reconfigure capture. Only the preview is mirrored.

`FaceFrameAnalyzer` is shared by reference-photo and live-frame analysis. Vision
detects one face and its landmarks, then evaluates capture quality using that
same face observation instead of running a second independent detector. Framing
feedback distinguishes distance, clipping, centering, head tilt and missing
features. Roll is normalized to a signed angle; modest natural head tilt is
accepted. Invalid references, unsupported cameras and inference errors fail closed.
Capture-quality scoring is optional: if that auxiliary request is unavailable,
the detected face can still be verified. Simulator tests explicitly select a
supported CPU compute device for Vision; physical devices retain automatic
hardware selection.

Five landmarks align each face to SFace's 112 × 112 template. The bundled Core ML
model receives RGB NHWC Float32 pixels in 0...255; its graph contains normalization.
The app normalizes its 128-dimensional output and compares cosine similarity.
The model, license, source and checksums are in `Resources/FaceVerification`.
The build system automatically compiles the model into the app bundle.

## Decision and liveness

**Tuned on a real iPhone 17 Pro (18 November 2026)**, from per-frame logs of
about fifteen scans (`FaceScanLog`, see below):

- Same-person scores against the profile photo were 0.51–0.73, so the default
  threshold is now 0.40 + 0.05 margin (OpenCV's reference SFace threshold is
  0.363). A *No match* needs at least six low frames over 1.5 seconds; a blink
  no longer ends the scan.
- Turning towards a ball measured motion radii of 6–10; only the direction
  counts now (frames above 25 are rejected as nonsense instead of above 4).
- Vision reports roll in 30° steps, so head tilts up to 0.8 rad are accepted.
- The face-jump check compares frames at most 0.3 s apart and tracks the face
  during pauses too.
- The final identity check accepts a frontal face up to 1.6 from the calibrated
  pose instead of 0.7.

Result: six of six complete scans matched in 7–10 seconds. To log again, launch
a debug build with `FACE_SCAN_LOG=1` (command in `FaceScanLog.swift`).

`FaceVerificationConfiguration` configures the cosine threshold (default 0.40),
uncertainty margin (0.05), preferred capture quality (0.3), deadline (45 seconds), face-loss limit (2.5 seconds)
and sample count (three to thirty). `FaceVerificationView` and its view model accept this
configuration. These are developer settings, separate from the user's dating
match percentage. The defaults are conservative starting values, **not measured
false-accept/false-reject guarantees**. Calibrate on representative, consented
same-person/different-person captures using this exact preprocessing before release.

The scanner calibrates a neutral pose from three matching frontal frames, then
asks for one small continuous head circle. A ring of forty ticks represents eight
actual captured motion sectors, in a randomized clockwise/counterclockwise order.
A large white target ball and a smaller cyan motion cursor share the same orbit,
so the user can actually bring them together. The accepted cone includes natural
vertical drift (40 degrees either side of the target). The motion signal is
smoothed (70% current / 30% previous) and calibrated for smaller head movements.

Each sector still needs evidence from two frames. The app accepts a stable near
hit or an observed continuous angular sweep through a target, without asking the
user to stop on it. Sweeps are bounded to nearby frames (0.06–0.5 seconds apart)
and angular changes below about 96 degrees; abrupt jumps cannot fill intervening
areas. At most two crossed sectors are collected per frame pair. The ring is
never filled by an elapsed-time animation. No intermediate left/right holds or
returns to center are required.

Head motion is measured from the nose relative to the eye line and mouth, with
translation, scale and in-plane roll removed, and calibrated to the user's neutral
pose. This also works when Vision does not provide `VNFaceObservation.pitch`.
Horizontal motion is mirrored to match the camera preview. Moving/rolling a flat
image in the frame does not alone produce the required relative landmark motion.
This is still basic motion liveness, not a certified spoof detector.

`FaceScanProgress` owns the entire production scan state machine. Every usable
frame reaches it, including frames between motion targets. The old pose-only
1.25-second timestamp reset has been removed. Brief missing landmarks/faces pause
collection but preserve collected sectors. A face loss longer than 2.5 seconds,
multiple faces, abrupt position changes, camera rotation or backward timestamps
ends the attempt with an explicit failure, without silently clearing the displayed
ring. Only the user's explicit retry starts an empty ring.

After all eight sectors are captured, the user returns to their calibrated neutral
position for a final identity comparison. Filling the ring alone cannot produce
**Match**: the initial and final frontal comparisons must clear the identity
threshold and uncertainty margin. A transient uncertain final frame retains the
ring and can recover; repeated uncertain identity samples return **Geen match**.

The verification screen uses the onboarding's navy background, cyan/violet
palette, translucent surfaces, rounded typography and shared gradient buttons.
It opens full screen, with a circular live preview, real collected ticks, a target
indicator, one short instruction and a plain percentage. Duplicate headings,
explanatory paragraphs and the privacy footer have been removed from the active
scan. A selection haptic confirms collected areas. Retry/result controls appear
only after an outcome. It supports
Reduce Motion and scrolls on smaller screens and at larger text sizes.

Vision capture quality ranks captures of the same face and includes expression
and pose. It is **not an absolute lighting test**. Frames below 0.3 no longer
reset or block the scan. Final matched frontal frames are ranked by quality:
prefer at least three above the quality preference, or select the best available
after a bounded 0.8-second collection interval. Missing quality scores receive
the lowest rank. At least three final samples must all clear the unchanged
identity threshold and uncertainty margin for **Match**.
Uncertain identity samples lead to **Geen match**. Incomplete liveness, permission
denial, interruption, cancellation, timeout or model errors produce
**Verificatie mislukt**. Both are unverified and support retrying.

This is **basic motion liveness**, which reduces simple static-photo/replay
attacks. It is not certified PAD, depth-based liveness or a guarantee against
screens, manipulated video or sophisticated replay. Verify prompts/signs,
usability and spoof resistance on physical iPhones before shipping.

## Lifecycle and storage

- No Face ID, LocalAuthentication, enrolled templates, microphone or network API
  is used by verification.
- Frames, aligned crops and embeddings stay in memory. Capture stops and the
  model, reference embedding and temporary samples are released on completion,
  cancellation, disappearance, backgrounding or interruption. Scans are never
  recorded, logged, uploaded, or added to a repository.
- The existing selected profile photo remains stored by the existing profile
  repository. This is distinct from the temporary live verification data.
- The result receipt is in memory, bound to the reference's UUID and SHA-256
  contents. It is not Codable and does not change profile or cloud schemas.
  Replacing the auto-matching photo or changing the onboarding main photo
  invalidates verification. A delayed result for another reference is ignored.
- Joining/saving auto matching and completing photo onboarding require a current
  successful result in their view models, in addition to the UI checks. New
  auto-matching uploads disable matching until verified and joined again.
  Because receipts are not persisted, a new app/view-model session requires a
  fresh scan before these actions. Already active matching is not migrated or
  disabled on app launch.
- This is a local client check, not a server-attested verification credential.

## Validation

`FaceVerificationTests` covers threshold/uncertainty behavior, invalid embeddings
and configuration, static faces, interrupted sequences, photo binding, onboarding gating, geometric alignment and execution
of the real bundled Core ML model. Camera regressions cover sensor-specific
rotation (including zero degrees), minor rotation jitter, normalized face roll,
specific framing feedback and bounded
selection when quality is below 0.3 or absent. Low-quality ranking never lowers
the identity threshold or bypasses liveness. `ProfileCreationViewModelTests` also checks that
joining auto matching needs verification and that replacement/stale results do
not retain verification. `FaceCircleScanTests` feeds complete frame sequences
through the same reducer as the camera: both circle directions, slow transitions,
short/long face loss, static faces, wrong sectors, initial/final identity gating,
uncertain final comparisons and landmark-pose invariance. Smooth-scan regressions
cover continuous sweeps without stops, the former 75%-stall with a slightly
lower-than-left pose, shared target/cursor geometry, stationary offset poses and
large angular jumps. `FaceVerificationLayoutTests`
renders active, compact, successful and retry states for visual inspection using
synthetic camera placeholders. No real scan images are saved by these renders.
Run the app's unit-test target on an iOS simulator.

Before release, test on physical iPhones: camera permission allow/deny/restricted,
Settings recovery, front-camera orientation and mirroring, both circle
directions, a real same-person match, a different person, uncertain scores, multiple
faces, occlusion, dim light, printed photos, screens/videos, timeout, cancellation,
phone lock/background, camera interruptions, retries and photo replacement.
The simulator cannot validate a real front-camera scan or real-world liveness.

References:

- [Apple: face capture quality and landmarks](https://developer.apple.com/documentation/vision/analyzing-a-selfie-and-visualizing-its-content)
- [Apple: camera authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)
- [Apple: sensor-specific rotation coordinator](https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator)
- [Apple: capture quality ranks captures of the same face](https://developer.apple.com/documentation/vision/selecting-a-selfie-based-on-capture-quality)
- [OpenCV SFace model and reference comparison](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface)
- [PINTO SFace Core ML conversion](https://github.com/PINTO0309/PINTO_model_zoo/tree/main/256_SFace)
