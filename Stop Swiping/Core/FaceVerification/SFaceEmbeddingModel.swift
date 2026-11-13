import CoreImage
import CoreML
import Vision

nonisolated enum FaceScanError: LocalizedError, Equatable {
    case unavailableModel, invalidModel, invalidPhoto, faceCount, poorQuality, missingLandmarks
    case cameraUnavailable, cameraConfiguration, multipleFaces

    var errorDescription: String? {
        switch self {
        case .unavailableModel: L10n("Face verification is unavailable on this device. Please try again later.")
        case .invalidModel: L10n("The face recognition model couldn’t process this scan.")
        case .invalidPhoto: L10n("This photo couldn’t be opened. Please choose another photo.")
        case .faceCount: L10n("Use a photo containing exactly one face: yours.")
        case .multipleFaces: L10n("Keep only your face in view. Other faces cannot be included in the scan.")
        case .poorQuality: L10n("Use a sharp, well-lit photo looking straight at the camera, with your whole face visible.")
        case .missingLandmarks: L10n("Your eyes, nose and mouth must be clearly visible. Please choose another photo.")
        case .cameraUnavailable: L10n("The front camera is unavailable. Try this on an iPhone with a front camera.")
        case .cameraConfiguration: L10n("The camera couldn’t be started. Close other camera apps and try again.")
        }
    }
}

/// Queue-confined. The bundled SFace conversion takes RGB NHWC values in 0...255.
/// Its graph includes (x - 127.5) / 128 normalization. No biometric writes or network access.
nonisolated final class SFaceEmbeddingModel {
    private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "SFace", withExtension: "mlmodelc") else {
            throw FaceScanError.unavailableModel
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName["data"]?.multiArrayConstraint?.shape
                == [1, 112, 112, 3],
              model.modelDescription.outputDescriptionsByName["Identity"]?.type == .multiArray else {
            throw FaceScanError.invalidModel
        }
    }

    func embedding(image: CIImage, face: VNFaceObservation) throws -> [Float] {
        let aligned = try FaceAlignment.aligned(image: image, face: face)
        return try embedding(alignedImage: aligned)
    }

    func embedding(alignedImage aligned: CIImage) throws -> [Float] {
        let input = try inputTensor(for: aligned)
        let features = try MLDictionaryFeatureProvider(dictionary: ["data": MLFeatureValue(multiArray: input)])
        guard let output = try model.prediction(from: features).featureValue(for: "Identity")?.multiArrayValue,
              output.count == 128 else { throw FaceScanError.invalidModel }
        return try Self.normalized((0..<output.count).map { output[$0].floatValue })
    }

    func inputTensor(for aligned: CIImage) throws -> MLMultiArray {
        var pixels = [UInt8](repeating: 0, count: 112 * 112 * 4)
        context.render(aligned, toBitmap: &pixels, rowBytes: 112 * 4,
                       bounds: CGRect(x: 0, y: 0, width: 112, height: 112),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let input = try MLMultiArray(shape: [1, 112, 112, 3], dataType: .float32)
        for y in 0..<112 {
            for x in 0..<112 {
                for channel in 0..<3 {
                    // CIContext renders bitmap rows top-to-bottom.
                    let value = Float(pixels[(y * 112 + x) * 4 + channel])
                    input[[0, NSNumber(value: y), NSNumber(value: x), NSNumber(value: channel)]] = NSNumber(value: value)
                }
            }
        }
        return input
    }

    static func normalized(_ values: [Float]) throws -> [Float] {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { throw FaceScanError.invalidModel }
        let norm = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0.000001 else { throw FaceScanError.invalidModel }
        return values.map { $0 / norm }
    }

    static func cosine(_ lhs: [Float], _ rhs: [Float]) throws -> Float {
        guard lhs.count == rhs.count else { throw FaceScanError.invalidModel }
        let a = try normalized(lhs)
        let b = try normalized(rhs)
        return min(1, max(-1, zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }))
    }
}

nonisolated enum FaceAlignment {
    /// SFace/ArcFace's five-point template, expressed in Core Image's y-up space.
    static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 112 - 51.6963), CGPoint(x: 73.5318, y: 112 - 51.5014),
        CGPoint(x: 56.0252, y: 112 - 71.7366), CGPoint(x: 41.5493, y: 112 - 92.3655),
        CGPoint(x: 70.7299, y: 112 - 92.2041)
    ]

    static func aligned(image: CIImage, face: VNFaceObservation) throws -> CIImage {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let nose = landmarks.noseCrest, let lips = landmarks.outerLips else {
            throw FaceScanError.missingLandmarks
        }
        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map { point in
                CGPoint(x: (face.boundingBox.minX + CGFloat(point.x) * face.boundingBox.width) * image.extent.width,
                        y: (face.boundingBox.minY + CGFloat(point.y) * face.boundingBox.height) * image.extent.height)
            }
        }
        func mean(_ points: [CGPoint]) throws -> CGPoint {
            guard !points.isEmpty else { throw FaceScanError.missingLandmarks }
            return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                           y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        }
        let eyes = try [mean(points(leftEye)), mean(points(rightEye))].sorted { $0.x < $1.x }
        guard let tip = points(nose).min(by: { $0.y < $1.y }),
              let mouthLeft = points(lips).min(by: { $0.x < $1.x }),
              let mouthRight = points(lips).max(by: { $0.x < $1.x }) else {
            throw FaceScanError.missingLandmarks
        }
        let transform = try similarityTransform(from: [eyes[0], eyes[1], tip, mouthLeft, mouthRight], to: template)
        return image.transformed(by: transform).cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
    }

    /// Least-squares rotation, uniform scale and translation; no reflection.
    static func similarityTransform(from source: [CGPoint], to target: [CGPoint]) throws -> CGAffineTransform {
        guard source.count == target.count, source.count >= 2,
              (source + target).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw FaceScanError.missingLandmarks
        }
        let count = CGFloat(source.count)
        let sourceMean = CGPoint(x: source.map(\.x).reduce(0, +) / count, y: source.map(\.y).reduce(0, +) / count)
        let targetMean = CGPoint(x: target.map(\.x).reduce(0, +) / count, y: target.map(\.y).reduce(0, +) / count)
        var denominator: CGFloat = 0
        var real: CGFloat = 0
        var imaginary: CGFloat = 0
        for (p, q) in zip(source, target) {
            let x = p.x - sourceMean.x, y = p.y - sourceMean.y
            let u = q.x - targetMean.x, v = q.y - targetMean.y
            denominator += x * x + y * y
            real += x * u + y * v
            imaginary += x * v - y * u
        }
        guard denominator > 0.000001 else { throw FaceScanError.missingLandmarks }
        let a = real / denominator, b = imaginary / denominator
        guard a.isFinite, b.isFinite, a * a + b * b > 0.000001 else { throw FaceScanError.missingLandmarks }
        return CGAffineTransform(a: a, b: b, c: -b, d: a,
                                 tx: targetMean.x - a * sourceMean.x + b * sourceMean.y,
                                 ty: targetMean.y - b * sourceMean.x - a * sourceMean.y)
    }
}
