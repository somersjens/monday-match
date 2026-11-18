import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class FaceVerificationViewModel: ObservableObject {
    @Published private(set) var camera: FaceVerificationCamera?
    @Published private(set) var snapshot = FaceScanSnapshot()
    @Published private(set) var outcome: FaceVerificationOutcome?
    @Published private(set) var needsCameraPermission = false

    private var startTask: Task<Void, Never>?
    private var generation = UUID()
    private let configuration: FaceVerificationConfiguration

    init(configuration: FaceVerificationConfiguration = .init()) {
        self.configuration = configuration
    }

    func start(referenceData: Data) {
        stop()
        outcome = nil
        needsCameraPermission = false
        snapshot = FaceScanSnapshot(instruction: L10n("Preparing your camera…"))
        let token = generation
        startTask = Task { [weak self] in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard !Task.isCancelled, let self, token == self.generation else { return }
            guard authorized else {
                self.needsCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) == .denied
                self.outcome = .failed(L10n("Camera access is required for a live scan. Allow camera access in Settings, then try again."))
                return
            }
            let camera = FaceVerificationCamera(configuration: self.configuration) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, token == self.generation else { return }
                    switch update {
                    case .guidance(let snapshot):
                        guard self.outcome == nil, snapshot.canReplace(self.snapshot) else { return }
                        self.snapshot = snapshot
                    case .finished(let outcome):
                        self.outcome = outcome
                        self.camera = nil
                    }
                }
            }
            self.camera = camera
            camera.start(referenceData: referenceData)
        }
    }

    func interrupt() {
        guard outcome == nil else { return }
        stop()
        outcome = .failed(L10n("The scan was interrupted. Please try again."))
    }

    func stop() {
        generation = UUID()
        startTask?.cancel()
        startTask = nil
        camera?.stop()
        camera = nil
    }
}

struct FaceVerificationView: View {
    let referencePhoto: ProfilePhoto
    let onComplete: (PhotoVerificationReceipt) -> Void

    @StateObject private var viewModel: FaceVerificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(referencePhoto: ProfilePhoto,
         configuration: FaceVerificationConfiguration = .init(),
         onComplete: @escaping (PhotoVerificationReceipt) -> Void) {
        self.referencePhoto = referencePhoto
        self.onComplete = onComplete
        _viewModel = StateObject(wrappedValue: FaceVerificationViewModel(configuration: configuration))
    }

    var body: some View {
        FaceVerificationScreen(
            snapshot: viewModel.snapshot,
            outcome: viewModel.outcome,
            needsCameraPermission: viewModel.needsCameraPermission,
            onCancel: { complete(.failed(L10n("Verification was cancelled. Start a new scan to verify this photo."))) },
            onRetry: { viewModel.start(referenceData: referencePhoto.imageData) },
            onSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            },
            onDone: { complete(viewModel.outcome ?? .failed(L10n("The scan was incomplete."))) }
        ) {
            if let camera = viewModel.camera {
                FaceCameraPreview(session: camera.session)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 100, weight: .ultraLight))
                    .foregroundStyle(OnboardingTheme.tertiaryText)
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: viewModel.snapshot.collectedSectors.count)
        .task { viewModel.start(referenceData: referencePhoto.imageData) }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && viewModel.camera != nil) { viewModel.interrupt() }
        }
    }

    private func complete(_ outcome: FaceVerificationOutcome) {
        viewModel.stop()
        onComplete(PhotoVerificationReceipt(photoID: referencePhoto.id, imageData: referencePhoto.imageData, outcome: outcome))
        dismiss()
    }
}

private struct FaceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.configure(session: session)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.configure(session: session)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: ()) {
        view.stopPreview()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        func configure(session: AVCaptureSession) {
            if previewLayer.session !== session { previewLayer.session = session }
            if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
               rotationCoordinator?.device !== device {
                rotationObservation?.invalidate()
                let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
                rotationCoordinator = rotation
                rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.updateRotation() }
                }
            }
            updateRotation()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateRotation()
        }

        private func updateRotation() {
            guard let rotationCoordinator, let connection = previewLayer.connection,
                  let angle = FaceCameraRotation.quarterTurn(for: rotationCoordinator.videoRotationAngleForHorizonLevelPreview) else { return }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }

        func stopPreview() {
            rotationObservation?.invalidate()
            rotationObservation = nil
            rotationCoordinator = nil
            previewLayer.session = nil
        }
    }
}
