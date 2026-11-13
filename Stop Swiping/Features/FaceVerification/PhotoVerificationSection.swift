import SwiftUI

/// Shared by both existing photo inputs; uses the selected upload as reference.
struct PhotoVerificationSection: View {
    let photo: ProfilePhoto?
    let receipt: PhotoVerificationReceipt?
    let onComplete: (PhotoVerificationReceipt) -> Void

    @State private var presentedPhoto: ProfilePhoto?

    private var outcome: FaceVerificationOutcome? {
        guard let photo, let receipt,
              receipt.belongs(to: photo.id, imageData: photo.imageData) else { return nil }
        return receipt.outcome
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n("Photo guidelines"), systemImage: "person.crop.rectangle.badge.checkmark")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                guideline(L10n("Use a recent, sharp photo of yourself, with exactly one face."))
                guideline(L10n("Face the camera. Show your full face, eyes, nose and mouth."))
                guideline(L10n("Use even lighting and a simple background. Avoid blur, shadows and backlighting."))
                guideline(L10n("Remove sunglasses, masks and anything covering your face. Avoid beauty filters, edits and AI images."))
                guideline(L10n("Choose the original photo rather than a screenshot or a photo of a screen. Your face should fill a clear part of the image."))
            }
            .font(.footnote)

            Divider()
            Label(L10n("Live face verification"), systemImage: "camera.viewfinder")
                .font(.subheadline.weight(.semibold))
            Text(L10n("We compare a live front-camera scan with this photo. Slowly move your head in a small circle to fill the ring. A match is required to continue with this photo."))
                .font(.footnote)
            if let outcome {
                Label(outcome.title, systemImage: outcome == .match ? "checkmark.shield.fill" : "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(outcome == .match ? Color.green : Color.orange)
                Text(outcome.message).font(.footnote)
            }
            Button(outcome == .match ? L10n("Verify again") : L10n("Verify this photo")) {
                presentedPhoto = photo
            }
            .buttonStyle(.bordered)
            .disabled(photo == nil)
            Text(L10n("Camera images and face features are processed locally and discarded after the scan. Your chosen profile photo is saved as before."))
                .font(.caption)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(item: $presentedPhoto) { reference in
            FaceVerificationView(referencePhoto: reference, onComplete: onComplete)
        }
    }

    private func guideline(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
