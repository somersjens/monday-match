import AVFoundation
import Combine
import SwiftUI

/// The rear camera, looking for QR codes. Capture state is confined to
/// `queue`; the preview layer only reads the session. Nothing is recorded.
nonisolated final class ProfileCodeCamera: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.stopswiping.profile-code", qos: .userInitiated)
    private let onCode: @Sendable (String) -> Void
    private var isConfigured = false
    /// Written on `queue` before `prepare` reports success, only read after.
    private(set) var device: AVCaptureDevice?

    init(onCode: @escaping @Sendable (String) -> Void) {
        self.onCode = onCode
    }

    /// Sets the session up without starting it. Reports whether it can run.
    func prepare(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if !isConfigured { isConfigured = configure() }
            completion(isConfigured)
        }
    }

    /// Reports whether the camera is running.
    func start(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard isConfigured else { return completion(false) }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning)
        }
    }

    /// Reports once the session has stopped.
    func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            completion?()
        }
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
        self.device = device
        output.metadataObjectTypes = [.qr]
        output.setMetadataObjectsDelegate(self, queue: queue)
        // A code on another phone is small and close.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        return true
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for case let code as AVMetadataMachineReadableCodeObject in metadataObjects {
            if let text = code.stringValue { onCode(text) }
        }
    }
}

@MainActor
final class ProfileCodeScannerModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case scanning
        /// The user has to allow the camera in Settings.
        case denied
        case unavailable
    }

    @Published private(set) var phase = Phase.starting
    /// Shown while the camera sees a QR code that isn't a profile.
    @Published private(set) var showsUnknownCode = false
    @Published private(set) var profile: ProfileCreationState?
    private(set) var camera: ProfileCodeCamera?
    /// Owned here rather than by SwiftUI: it joins the session before the
    /// session starts and leaves only after it has stopped. Attaching or
    /// detaching a preview while the session starts or stops waits for it on
    /// the main thread, which froze the app for a moment on closing.
    private(set) lazy var preview = ProfileCodeCameraPreviewView()
    private var isClosed = false
    private var unknownCodeTask: Task<Void, Never>?
    private var lastRejected: String?

    func start() {
        guard camera == nil, !isClosed else { return }
        Task { [weak self] in
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard authorized else {
                self?.phase = .denied
                return
            }
            guard let self, camera == nil, !isClosed else { return }
            let camera = ProfileCodeCamera { [weak self] text in
                Task { @MainActor [weak self] in self?.read(text) }
            }
            self.camera = camera
            let ready = await withCheckedContinuation { continuation in
                camera.prepare { continuation.resume(returning: $0) }
            }
            guard !isClosed else { return }
            guard ready else {
                phase = .unavailable
                return
            }
            preview.attach(camera)
            camera.start { [weak self] running in
                Task { @MainActor [weak self] in self?.phase = running ? .scanning : .unavailable }
            }
        }
    }

    /// Picks up again after the app comes back to the foreground.
    func resume() {
        guard !isClosed, profile == nil, phase == .scanning else { return }
        camera?.start { _ in }
    }

    /// Stops the camera; `resume` can start it again.
    func pause() {
        unknownCodeTask?.cancel()
        camera?.stop()
    }

    /// Stops the camera for good. The preview lets go of the session only
    /// once it has stopped, off the main thread.
    func close() {
        isClosed = true
        unknownCodeTask?.cancel()
        guard let camera else { return }
        let preview = preview
        camera.stop {
            Task { @MainActor in preview.detach() }
        }
    }

    /// Decodes what the camera read. The first profile found ends the scan.
    func read(_ text: String, today: CalendarDate? = nil) {
        guard profile == nil else { return }
        let today = today ?? .today()
        // The camera reports the same code many times a second.
        if text == lastRejected {
            if showsUnknownCode { showUnknownCode() }
            return
        }
        if let scanned = ProfileCode.profile(fromScanned: text, today: today) {
            profile = scanned
            showsUnknownCode = false
            pause()
        } else {
            lastRejected = text
            showUnknownCode()
        }
    }

    private func showUnknownCode() {
        showsUnknownCode = true
        unknownCodeTask?.cancel()
        unknownCodeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.showsUnknownCode = false
            self?.lastRejected = nil
        }
    }
}

/// Scans another person's profile code without leaving the app.
struct ProfileCodeScannerView: View {
    let onScan: (ProfileCreationState) -> Void
    let onClose: () -> Void

    @StateObject private var model = ProfileCodeScannerModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let side = max(120, min(min(proxy.size.width - 72, proxy.size.height - 320), 300))
            // The window sits in the middle; the text fills the space above
            // it and the hints the space below.
            let margin = max(0, (proxy.size.height - side) / 2 - 24)
            ZStack {
                OnboardingTheme.background.ignoresSafeArea()

                if model.phase == .scanning {
                    ProfileCodeCameraPreview(view: model.preview)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    ScannerWindow(side: side)
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                }

                viewfinder(side: side)

                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(OnboardingTheme.accentGradient)
                                    .frame(width: 44, height: 44)
                                    .background { Circle().fill(.white.opacity(0.08)) }
                                    .overlay { Circle().strokeBorder(OnboardingTheme.hairline, lineWidth: 0.5) }
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n("Close"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Spacer(minLength: 8)

                        VStack(spacing: 8) {
                            Text(title)
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                                .foregroundStyle(OnboardingTheme.primaryText)
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .padding(.horizontal, 28)
                        .accessibilityElement(children: .combine)
                    }
                    .frame(height: margin)

                    Spacer(minLength: 0)

                    footer
                        .padding(.horizontal, 28)
                        .frame(height: margin, alignment: .top)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .animation(.easeInOut(duration: 0.25), value: model.showsUnknownCode)
        .sensoryFeedback(.success, trigger: model.profile) { _, profile in profile != nil }
        .sensoryFeedback(.warning, trigger: model.showsUnknownCode) { _, shown in shown }
        .onAppear { model.start() }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.resume()
            } else if phase == .background {
                model.pause()
            }
        }
        .onChange(of: model.profile) { _, profile in
            if let profile { onScan(profile) }
        }
    }

    private var title: String {
        switch model.phase {
        case .starting, .scanning: L10n("Scan their code")
        case .denied: L10n("Camera access needed")
        case .unavailable: L10n("Camera unavailable")
        }
    }

    private var message: String {
        switch model.phase {
        case .starting, .scanning:
            L10n("Point your camera at the code on the other person’s screen. You’ll see right here whether you’re a match.")
        case .denied:
            L10n("Allow camera access in Settings to scan a code. You can also scan it with your iPhone’s Camera app.")
        case .unavailable:
            L10n("This device’s camera can’t be used right now. You can also scan the code with your iPhone’s Camera app.")
        }
    }

    private func viewfinder(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .strokeBorder(OnboardingTheme.accentGradient.opacity(model.phase == .scanning ? 0.9 : 0.35), lineWidth: 2)
            .frame(width: side, height: side)
            .background {
                if model.phase != .scanning {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(OnboardingTheme.surface)
                    Group {
                        if model.phase == .starting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(OnboardingTheme.tertiaryText)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(OnboardingTheme.pink)
                                        .offset(x: 8, y: 6)
                                }
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .denied:
            Button(L10n("Open Settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(GlowButtonStyle())
            .frame(maxWidth: OnboardingTheme.controlWidth)
        case .scanning where model.showsUnknownCode:
            Label(L10n("That isn’t a Stop Swiping code."), systemImage: "qrcode")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        default:
            EmptyView()
        }
    }
}

/// The whole screen, safe areas included, with the scanning window cut out.
private struct ScannerWindow: Shape {
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -400, dy: -400))
        path.addRoundedRect(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side),
                            cornerSize: CGSize(width: 34, height: 34), style: .continuous)
        return path
    }
}

/// Shows the model's preview; the model decides when it joins the session.
private struct ProfileCodeCameraPreview: UIViewRepresentable {
    let view: ProfileCodeCameraPreviewView

    func makeUIView(context: Context) -> ProfileCodeCameraPreviewView { view }

    func updateUIView(_ view: ProfileCodeCameraPreviewView, context: Context) {}
}

final class ProfileCodeCameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Call while the session is stopped.
    func attach(_ camera: ProfileCodeCamera) {
        previewLayer.session = camera.session
        guard let device = camera.device else { return }
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = rotation
        rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview,
                                               options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateRotation() }
        }
    }

    /// Call once the session has stopped.
    func detach() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        previewLayer.session = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRotation()
    }

    private func updateRotation() {
        guard let rotationCoordinator, let connection = previewLayer.connection else { return }
        let angle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
    }
}
