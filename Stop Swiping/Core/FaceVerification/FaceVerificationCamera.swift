import AVFoundation
import CoreImage
import ImageIO
import Vision

nonisolated enum FaceScanUpdate: Sendable {
    case guidance(FaceScanSnapshot)
    case finished(FaceVerificationOutcome)
}

/// All mutable capture, Vision and Core ML state is confined to `queue`.
/// The preview layer only reads the session. Frames are never recorded.
nonisolated final class FaceVerificationCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.stopswiping.face-verification", qos: .userInitiated)
    private let configuration: FaceVerificationConfiguration
    private let onUpdate: @Sendable (FaceScanUpdate) -> Void
    private var model: SFaceEmbeddingModel?
    private var referenceEmbedding: [Float]?
    private let analyzer = FaceFrameAnalyzer()
    private var scanProgress: FaceScanProgress
    private var lastFrameTime: TimeInterval = -.infinity
    private var lastFaceBox: CGRect?
    private var lastGuidance = L10n("Look straight at the camera and hold still.")
    private var isScanning = false
    private var didFinish = false
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var videoConnection: AVCaptureConnection?

    init(configuration: FaceVerificationConfiguration,
         onUpdate: @escaping @Sendable (FaceScanUpdate) -> Void) {
        self.configuration = configuration
        scanProgress = FaceScanProgress(configuration: configuration)
        self.onUpdate = onUpdate
    }

    func start(referenceData: Data) {
        queue.async { [self] in
            do {
                guard configuration.isValid else { throw FaceScanError.invalidModel }
                let model = try SFaceEmbeddingModel()
                guard let image = CIImage(data: referenceData, options: [.applyOrientationProperty: true]) else {
                    throw FaceScanError.invalidPhoto
                }
                let upright = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                let analyzed = try analyzer.analyze(upright)
                guard analyzed.geometry.guidance == .ready, abs(analyzed.face.yaw?.doubleValue ?? .infinity) <= 0.35 else {
                    throw FaceScanError.poorQuality
                }
                referenceEmbedding = try model.embedding(image: upright, face: analyzed.face)
                self.model = model
                try configureCamera()
                isScanning = true
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + configuration.timeout)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.finish(.failed(L10n("The scan timed out. \(self.lastGuidance) Then try again.")))
                }
                self.timer = timer
                timer.resume()
                session.startRunning()
                guard session.isRunning else { throw FaceScanError.cameraConfiguration }
                publishProgress()
            } catch {
                finish(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        queue.async { [self] in cleanUp() }
    }

    private func configureCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw FaceScanError.cameraUnavailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canSetSessionPreset(.hd1280x720) else { throw FaceScanError.cameraConfiguration }
        session.sessionPreset = .hd1280x720
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw FaceScanError.cameraConfiguration }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw FaceScanError.cameraConfiguration }
        session.addOutput(output)
        guard let connection = output.connection(with: .video) else {
            throw FaceScanError.cameraConfiguration
        }
        // The sensor's portrait angle differs across iPhone generations.
        // Query AVFoundation instead of assuming 90 degrees for every camera.
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        guard let angle = FaceCameraRotation.quarterTurn(for: rotation.videoRotationAngleForHorizonLevelCapture),
              connection.isVideoRotationAngleSupported(angle) else { throw FaceScanError.cameraConfiguration }
        connection.videoRotationAngle = angle
        videoConnection = connection
        rotationCoordinator = rotation
        rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] rotation, _ in
            guard let self,
                  let angle = FaceCameraRotation.quarterTurn(for: rotation.videoRotationAngleForHorizonLevelCapture) else { return }
            self.queue.async { [self] in
                guard self.isScanning, let connection = self.videoConnection,
                      connection.videoRotationAngle != angle else { return }
                guard connection.isVideoRotationAngleSupported(angle) else {
                    self.finish(.failed(L10n("This camera rotation is unsupported. Hold your phone upright and try again.")))
                    return
                }
                connection.videoRotationAngle = angle
                self.finish(.failed(L10n("The phone rotated during the scan. Keep it upright and start a new scan.")))
            }
        }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }

        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [self] in
                    guard self.isScanning else { return }
                    self.finish(.failed(L10n("The camera was interrupted. Please start a new scan.")))
                }
            })
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isScanning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Motion feedback needs a higher cadence; expensive identity/quality
        // comparisons remain at six frames per second before/after the circle.
        let interval = scanProgress.needsIdentity ? 0.16 : 1.0 / 12.0
        guard now - lastFrameTime >= interval else { return }
        lastFrameTime = now
        autoreleasepool {
            do {
                guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                      let model, let referenceEmbedding else { throw FaceScanError.invalidModel }
                let image = CIImage(cvPixelBuffer: buffer)
                let analyzed: AnalyzedFaceFrame
                do {
                    analyzed = try analyzer.analyze(image, includeCaptureQuality: scanProgress.needsIdentity)
                } catch FaceScanError.faceCount {
                    pauseScan(message: L10n("Face inside the circle"), at: now)
                    return
                } catch FaceScanError.multipleFaces {
                    finish(.failed(L10n("Another face entered the scan. Keep only your face in view and try again.")))
                    return
                }
                let guidance = analyzed.geometry.guidance
                guard guidance == .ready, let pose = analyzed.headPose else {
                    pauseScan(message: guidance == .ready ? L10n("Show your eyes, nose and mouth") : guidance.message, at: now)
                    return
                }
                let face = analyzed.face
                if let previous = lastFaceBox {
                    let intersection = previous.intersection(face.boundingBox)
                    let overlap = intersection.isNull ? 0 : intersection.width * intersection.height
                    if overlap / max(previous.width * previous.height, 0.0001) < 0.35 {
                        finish(.failed(L10n("The face moved out of the scan. Start again with your face inside the circle.")))
                        return
                    }
                }
                lastFaceBox = face.boundingBox
                var score: Float?
                if scanProgress.needsIdentity, abs(pose.yaw) <= 0.35 {
                    let embedding = try model.embedding(image: image, face: face)
                    score = try SFaceEmbeddingModel.cosine(referenceEmbedding, embedding)
                }
                // Every usable motion frame reaches the same state machine.
                // There is no pose-only timestamp or hidden progress reset.
                scanProgress.accept(pose: pose, identityScore: score, quality: analyzed.captureQuality, at: now)
                publishProgress()
                if let outcome = scanProgress.outcome { finish(outcome) }
            } catch FaceScanError.missingLandmarks {
                pauseScan(message: L10n("Show your eyes, nose and mouth"), at: now)
            } catch {
                finish(.failed(error.localizedDescription))
            }
        }
    }

    private func publishProgress() {
        lastGuidance = scanProgress.snapshot.instruction
        onUpdate(.guidance(scanProgress.snapshot))
    }

    private func pauseScan(message: String, at timestamp: TimeInterval) {
        scanProgress.pause(message: message, at: timestamp)
        publishProgress()
        if let outcome = scanProgress.outcome { finish(outcome) }
    }

    private func finish(_ outcome: FaceVerificationOutcome) {
        guard !didFinish else { return }
        didFinish = true
        isScanning = false
        // Let any in-flight sample callback return before stopping capture.
        queue.async { [self] in
            cleanUp()
            onUpdate(.finished(outcome))
        }
    }

    private func cleanUp() {
        isScanning = false
        timer?.cancel()
        timer = nil
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
        referenceEmbedding = nil
        model = nil
        scanProgress = FaceScanProgress(configuration: configuration)
        lastFaceBox = nil
    }
}
