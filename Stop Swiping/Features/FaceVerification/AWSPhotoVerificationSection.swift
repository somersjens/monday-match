import AVFoundation
import FaceLiveness
import SwiftUI

struct AWSPhotoVerificationSection: View {
    let photo: ProfilePhoto
    let service: AWSPhotoVerificationService
    let receipt: PhotoVerificationReceipt?
    let onComplete: (PhotoVerificationReceipt) -> Void
    @State private var showsConsent=false
    @State private var session: AWSPhotoVerificationSession?
    @State private var isStarting=false
    @State private var error: String?
    private var verified: Bool { receipt?.belongs(to:photo.id,imageData:photo.imageData)==true && receipt?.outcome == .match }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Label(L10n("Server photo verification"),systemImage:"checkmark.shield")
                .font(.subheadline.weight(.semibold))
            Text(L10n("Use a recent, sharp photo of yourself, with exactly one face."))
                .font(.footnote)
            if verified { Label(L10n("Photo verified"),systemImage:"checkmark.shield.fill").foregroundStyle(.green) }
            if let error { Text(L10n(AppLocalizedMessage(stringLiteral:error))).font(.footnote).foregroundStyle(.orange) }
            Button(verified ? L10n("Verify again") : L10n("Verify this photo")) { showsConsent=true }
                .buttonStyle(.bordered).disabled(isStarting)
            if isStarting { ProgressView() }
        }
        .task(id:photo.id) {
            if !verified, (try? await service.photoIsVerified()) == true {
                onComplete(PhotoVerificationReceipt(photoID:photo.id,imageData:photo.imageData,outcome:.match))
            }
        }
        .sheet(isPresented:$showsConsent) {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text(L10n("Verify with AWS in Ireland")).font(.title2.bold())
                        Text(L10n("For this optional check, your live face video is sent directly to Amazon Web Services in Ireland. The server sends your selected profile photo to AWS to compare it with the live capture."))
                        Text(L10n("AWS checks that a real person is present and that the face matches your photo. This uses facial biometric analysis. Supabase saves the verification result and photo version, not the video or face features."))
                        Text(L10n("You can cancel or continue without a photo. You can request up to five checks per day. Only a server-confirmed result counts as a verified photo."))
                        Link(L10n("AWS Face Liveness privacy information"),destination:URL(string:"https://docs.aws.amazon.com/rekognition/latest/dg/face-liveness-faq.html")!)
                        Button(L10n("I agree — start verification")) {
                            showsConsent=false; Task { await start() }
                        }.buttonStyle(.borderedProminent)
                    }.padding(24)
                }.navigationTitle(L10n("Photo verification"))
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button(L10n("Cancel")) { showsConsent=false } } }
            }.presentationDetents([.large])
        }
        .fullScreenCover(item:$session) { session in
            AWSPhotoScan(session:session,service:service) { result in
                self.session=nil
                switch result {
                case .success:
                    error=nil; onComplete(PhotoVerificationReceipt(photoID:photo.id,imageData:photo.imageData,outcome:.match))
                case .failure(let failure): error=failure.localizedDescription
                }
            }
        }
    }
    private func start() async {
        isStarting=true; defer { isStarting=false }
        var granted=AVCaptureDevice.authorizationStatus(for:.video) == .authorized
        if AVCaptureDevice.authorizationStatus(for:.video) == .notDetermined { granted=await AVCaptureDevice.requestAccess(for:.video) }
        guard granted else { error=L10n("Camera access is required for this check."); return }
        do { session=try await service.start(photoID:photo.id); error=nil }
        catch { self.error=error.localizedDescription }
    }
}
private struct AWSPhotoScan: View {
    let session: AWSPhotoVerificationSession
    let service: AWSPhotoVerificationService
    let onComplete: (Result<Void,Error>) -> Void
    @State private var detectorPresented=true
    @State private var scanFinished=false
    var body: some View {
        Group {
            if detectorPresented {
                FaceLivenessDetectorView(sessionID:session.sessionID,
                    credentialsProvider:AWSLivenessCredentialProvider(credentials:session.credentials),region:session.region,
                    isPresented:$detectorPresented) { result in
                        switch result {
                        case .success: detectorPresented=false; scanFinished=true
                        case .failure(let error): onComplete(.failure(error))
                        }
                    }
            } else { ProgressView(L10n("The server is verifying your photo…")) }
        }
        .task(id:scanFinished) {
            guard scanFinished else { return }
            do { try await service.complete(session); onComplete(.success(())) }
            catch { if !Task.isCancelled { onComplete(.failure(error)) } }
        }
    }
}
