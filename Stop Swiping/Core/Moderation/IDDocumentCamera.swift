import AVFoundation
import Vision

nonisolated enum IDDocumentCameraUpdate: Sendable {
    /// The text lines read in one frame, top to bottom.
    case lines([String])
    case failed(String)
}

/// The rear camera, reading text from a passport or ID card held in the
/// scan frame. Only the text lines leave this class; frames are never kept
/// or recorded. All capture and Vision state is confined to `queue`.
nonisolated final class IDDocumentCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.stopswiping.id-document", qos: .userInitiated)
    /// Width over height of the frame the preview fills. Only what shows in
    /// it is read, so a document beside the frame doesn't count.
    private let frameAspect: CGFloat
    private let onUpdate: @Sendable (IDDocumentCameraUpdate) -> Void
    private var isScanning = false
    private var didFinish = false
    private var lastFrameTime: TimeInterval = -.infinity
    private var observers: [NSObjectProtocol] = []
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var videoConnection: AVCaptureConnection?

    init(frameAspect: CGFloat, onUpdate: @escaping @Sendable (IDDocumentCameraUpdate) -> Void) {
        self.frameAspect = frameAspect
        self.onUpdate = onUpdate
    }

    func start() {
        queue.async { [self] in
            do {
                try configureCamera()
                isScanning = true
                session.startRunning()
                guard session.isRunning else { throw IDDocumentCameraError.configuration }
            } catch IDDocumentCameraError.unavailable {
                finish(L10n("This device has no camera to scan your document with."))
            } catch {
                finish(L10n("The camera couldn’t be started. Please try again."))
            }
        }
    }

    func stop() {
        queue.async { [self] in cleanUp() }
    }

    private func configureCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw IDDocumentCameraError.unavailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // The zone's small print needs the extra pixels.
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw IDDocumentCameraError.configuration }
        session.addInput(input)

        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
        device.videoZoomFactor = Self.zoomFactor(minimumFocusDistance: Float(device.minimumFocusDistance),
                                                 fieldOfView: device.activeFormat.videoFieldOfView,
                                                 maximum: device.activeFormat.videoMaxZoomFactor)
        device.unlockForConfiguration()

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw IDDocumentCameraError.configuration }
        session.addOutput(output)
        guard let connection = output.connection(with: .video) else { throw IDDocumentCameraError.configuration }

        // Frames upright, like the preview, so text reads left to right.
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        if let angle = FaceCameraRotation.quarterTurn(for: rotation.videoRotationAngleForHorizonLevelCapture),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        videoConnection = connection
        rotationCoordinator = rotation
        rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] rotation, _ in
            guard let self,
                  let angle = FaceCameraRotation.quarterTurn(for: rotation.videoRotationAngleForHorizonLevelCapture) else { return }
            self.queue.async { [self] in
                guard let connection = self.videoConnection, connection.videoRotationAngle != angle,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }

        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    guard self.isScanning else { return }
                    self.finish(L10n("The camera was interrupted. Please try again."))
                }
            })
        }
    }

    /// Close enough to read the small print, far enough for the lens to
    /// focus: an ID card filling the frame's width would sit closer than
    /// most iPhones can focus, so zoom in until it can be held farther away.
    /// `fieldOfView` is the format's horizontal angle in degrees, along the
    /// sensor's long side; held upright, the frame's width is the short side.
    static func zoomFactor(minimumFocusDistance: Float, fieldOfView: Float, maximum: CGFloat) -> CGFloat {
        guard minimumFocusDistance > 0, fieldOfView > 0, fieldOfView < 180 else { return 1 }
        let halfAngle = atan(tan(Double(fieldOfView) * .pi / 360) * 9 / 16)
        // An ID card (85.6 mm) across 90 % of the frame.
        let distance = 85.6 / 0.9 / 2 / tan(halfAngle)
        guard distance < Double(minimumFocusDistance) else { return 1 }
        return max(1, min(maximum, 3, CGFloat(Double(minimumFocusDistance) / distance)))
    }

    /// The part of a frame the preview shows when it fills a frame of
    /// `frameAspect`, in Vision's normalised coordinates.
    static func visibleRegion(bufferAspect: CGFloat, frameAspect: CGFloat) -> CGRect {
        guard bufferAspect > 0, frameAspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        if bufferAspect < frameAspect {
            let height = bufferAspect / frameAspect
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
        let width = frameAspect / bufferAspect
        return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isScanning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Accurate recognition takes a while; a few frames a second is plenty.
        guard now - lastFrameTime >= 0.2 else { return }
        lastFrameTime = now
        autoreleasepool {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let width = CGFloat(CVPixelBufferGetWidth(buffer)), height = CGFloat(CVPixelBufferGetHeight(buffer))
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // The zone is not language: correction would "fix" it.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.regionOfInterest = Self.visibleRegion(bufferAspect: width / max(height, 1), frameAspect: frameAspect)
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            guard (try? handler.perform([request])) != nil else { return }
            let pieces = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { RecognisedTextRows.Piece(text: $0.string, box: observation.boundingBox) }
            }
            let lines = RecognisedTextRows.join(pieces)
            FaceScanLog.line("id lines=\(lines.filter { $0.contains("<") })")
            onUpdate(.lines(lines))
        }
    }

    private func finish(_ message: String) {
        guard !didFinish else { return }
        didFinish = true
        isScanning = false
        queue.async { [self] in
            cleanUp()
            onUpdate(.failed(message))
        }
    }

    private func cleanUp() {
        isScanning = false
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        videoConnection = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        session.stopRunning()
        for output in session.outputs {
            (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(output)
        }
        for input in session.inputs { session.removeInput(input) }
    }
}

nonisolated enum IDDocumentCameraError: Error {
    case unavailable
    case configuration
}
