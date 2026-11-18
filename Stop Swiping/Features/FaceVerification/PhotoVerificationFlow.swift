import AVFoundation
import SwiftUI

/// What the photo check is doing, for the control that starts it.
struct PhotoVerificationState: Equatable {
    /// The scan matched and the result is being sent to the server.
    var isSaving = false
    var issue: PhotoVerificationIssue?
}

/// Why a check did not go through, in the person's terms. The scan screen
/// itself already explained cancellations and other incomplete scans.
enum PhotoVerificationIssue: Equatable {
    /// The scan matched, but the server could not record it.
    case serviceUnavailable
    /// The scan ended, but did not confirm the face in this photo.
    case noMatch
    case cameraAccess

    var symbol: String {
        switch self {
        case .serviceUnavailable: "icloud.slash"
        case .noMatch: "person.crop.circle.badge.questionmark"
        case .cameraAccess: "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .serviceUnavailable: L10n("Verification isn’t working right now")
        case .noMatch: L10n("This photo doesn’t match you")
        case .cameraAccess: L10n("Camera access needed")
        }
    }

    var message: String {
        switch self {
        case .serviceUnavailable:
            L10n("That’s on our side, not yours. Please try again in a few minutes.")
        case .noMatch:
            L10n("Choose a clear, recent photo of just you, then slowly move your head in a circle during the scan.")
        case .cameraAccess:
            L10n("Allow camera access in Settings to verify your photo.")
        }
    }
}

extension View {
    /// Hosts the on-device photo check: the full-screen live scan and, after a
    /// match, telling the server. Setting `isPresented` starts the scan; a
    /// confirmed match is reported through `onComplete`.
    func photoVerification(
        photo: ProfilePhoto?,
        service: PhotoVerificationService?,
        isVerified: Bool,
        isPresented: Binding<Bool>,
        state: Binding<PhotoVerificationState>,
        onComplete: @escaping (PhotoVerificationReceipt) -> Void
    ) -> some View {
        modifier(PhotoVerificationFlow(photo: photo, service: service, isVerified: isVerified,
                                       isPresented: isPresented, state: state, onComplete: onComplete))
    }
}

private struct PhotoVerificationFlow: ViewModifier {
    let photo: ProfilePhoto?
    let service: PhotoVerificationService?
    let isVerified: Bool
    @Binding var isPresented: Bool
    @Binding var state: PhotoVerificationState
    let onComplete: (PhotoVerificationReceipt) -> Void

    func body(content: Content) -> some View {
        content
            .task(id: photo?.id) {
                // A photo the server already verified, for example after a reinstall.
                guard let photo, let service, !isVerified,
                      (try? await service.photoIsVerified()) == true else { return }
                onComplete(PhotoVerificationReceipt(photoID: photo.id, imageData: photo.imageData, outcome: .match))
            }
            .onChange(of: isPresented) { _, presented in
                if presented { state.issue = nil }
            }
            .fullScreenCover(isPresented: $isPresented) {
                if let photo {
                    FaceVerificationView(referencePhoto: photo) { receipt in
                        Task { await finish(receipt) }
                    }
                }
            }
    }

    private func finish(_ receipt: PhotoVerificationReceipt) async {
        switch receipt.outcome {
        case .match:
            if let service {
                state.isSaving = true
                defer { state.isSaving = false }
                do {
                    try await service.recordDeviceScan(photoID: receipt.photoID)
                } catch {
                    state.issue = .serviceUnavailable
                    return
                }
            }
            state.issue = nil
            onComplete(receipt)
        case .noMatch:
            state.issue = .noMatch
        case .failed:
            let camera = AVCaptureDevice.authorizationStatus(for: .video)
            state.issue = camera == .denied || camera == .restricted ? .cameraAccess : nil
        }
    }
}
