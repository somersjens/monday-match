import CoreImage
import CoreML
import Vision

nonisolated enum FaceCaptureGuidance: Equatable {
    case ready, moveCloser, moveBack, centerFace, levelPhone, faceCamera, showFeatures

    var message: String {
        switch self {
        case .ready: L10n("Face detected.")
        case .moveCloser: L10n("Move a little closer")
        case .moveBack: L10n("Move a little farther away")
        case .centerFace: L10n("Center your face")
        case .levelPhone: L10n("Keep your phone upright")
        case .faceCamera: L10n("Look at the camera")
        case .showFeatures: L10n("Show your eyes, nose and mouth")
        }
    }
}

nonisolated struct FaceCaptureGeometry {
    let boundingBox: CGRect
    let imageSize: CGSize
    let confidence: Float
    let roll: Double?
    let yaw: Double?
    let hasLandmarks: Bool

    static func normalizedAngle(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }

    var guidance: FaceCaptureGuidance {
        guard confidence.isFinite, confidence >= 0.9, hasLandmarks else { return .showFeatures }
        let box = boundingBox
        guard box.width.isFinite, box.height.isFinite, box.minX.isFinite, box.minY.isFinite,
              imageSize.width.isFinite, imageSize.height.isFinite,
              box.width > 0, box.height > 0, imageSize.width > 0, imageSize.height > 0 else { return .centerFace }
        guard box.width * imageSize.width >= 100, box.height * imageSize.height >= 100 else { return .moveCloser }
        guard box.width < 0.95, box.height < 0.95,
              box.minX >= -0.01, box.maxX <= 1.01, box.minY >= -0.01, box.maxY <= 1.01 else { return .moveBack }
        guard (0.15...0.85).contains(box.midX), (0.15...0.85).contains(box.midY) else { return .centerFace }
        guard let roll, roll.isFinite, abs(Self.normalizedAngle(roll)) <= 0.5 else { return .levelPhone }
        guard let yaw, yaw.isFinite, abs(yaw) <= 1.05 else { return .faceCamera }
        return .ready
    }
}

nonisolated struct AnalyzedFaceFrame {
    let face: VNFaceObservation
    let captureQuality: Float?
    let geometry: FaceCaptureGeometry
    let headPose: FaceHeadPose?
}

/// Used for reference photos AND camera frames, so their orientation, detection
/// and admissibility can be exercised without an actual capture session.
nonisolated final class FaceFrameAnalyzer {
    func analyze(_ image: CIImage, includeCaptureQuality: Bool = true) throws -> AnalyzedFaceFrame {
        let landmarks = VNDetectFaceLandmarksRequest()
        try configureComputeDevice(landmarks)
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up)
        try handler.perform([landmarks])
        guard let faces = landmarks.results, !faces.isEmpty else { throw FaceScanError.faceCount }
        guard faces.count == 1 else { throw FaceScanError.multipleFaces }
        let face = faces[0]
        let quality = VNDetectFaceCaptureQualityRequest()
        // Reuse the very same face; don't run a second independent detector
        // whose face count/bounds may disagree with the landmarks request.
        quality.inputFaceObservations = [face]
        // Capture quality is optional ranking information. Failure of this
        // auxiliary request must not invalidate usable face landmarks.
        if includeCaptureQuality, (try? configureComputeDevice(quality)) != nil {
            try? handler.perform([quality])
        }
        let features = face.landmarks
        let hasFeatures = [features?.leftEye, features?.rightEye, features?.noseCrest, features?.outerLips]
            .allSatisfy { ($0?.pointCount ?? 0) > 0 }
        return AnalyzedFaceFrame(
            face: face,
            captureQuality: quality.results?.first?.faceCaptureQuality,
            geometry: FaceCaptureGeometry(boundingBox: face.boundingBox, imageSize: image.extent.size,
                                          confidence: face.confidence, roll: face.roll?.doubleValue,
                                          yaw: face.yaw?.doubleValue, hasLandmarks: hasFeatures),
            headPose: headPose(face: face, imageSize: image.extent.size)
        )
    }

    private func headPose(face: VNFaceObservation, imageSize: CGSize) -> FaceHeadPose? {
        guard let landmarks = face.landmarks, let yaw = face.yaw?.doubleValue else { return nil }
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.normalizedPoints ?? []).map {
                CGPoint(x: CGFloat($0.x) * face.boundingBox.width * imageSize.width,
                        y: CGFloat($0.y) * face.boundingBox.height * imageSize.height)
            }
        }
        func mean(_ points: [CGPoint]) -> CGPoint? {
            guard !points.isEmpty else { return nil }
            return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                           y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        }
        guard let a = mean(points(landmarks.leftEye)), let b = mean(points(landmarks.rightEye)),
              let nose = points(landmarks.noseCrest).min(by: { $0.y < $1.y }),
              let mouth = mean(points(landmarks.outerLips)) else { return nil }
        return FaceHeadPose.estimate(eyeA: a, eyeB: b, nose: nose, mouth: mouth, yaw: yaw)
    }

    private func configureComputeDevice(_ request: VNRequest) throws {
        #if targetEnvironment(simulator)
        // The simulator has no Neural Engine; automatic device selection can
        // fail with Vision error 9 even for a valid, raster-backed image.
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }
}
