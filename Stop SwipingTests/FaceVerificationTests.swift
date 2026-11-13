import AVFoundation
import CoreImage
import CoreML
import XCTest
@testable import Stop_Swiping

@MainActor
final class FaceVerificationTests: XCTestCase {
    func testDecisionRequiresEverySampleToClearThresholdAndUncertaintyMargin() {
        let config = FaceVerificationConfiguration()
        XCTAssertEqual(config.decision(scores: [0.8, 0.7, 0.9], livenessPassed: true), .match)
        XCTAssertEqual(config.decision(scores: [0.8, 0.59, 0.9], livenessPassed: true), .noMatch)
        XCTAssertEqual(config.decision(scores: [0.2, 0.3, 0.4], livenessPassed: true), .noMatch)
        XCTAssertNotEqual(config.decision(scores: [0.9, 0.9], livenessPassed: true), .match)
        XCTAssertNotEqual(config.decision(scores: [0.9, 0.9, 0.9], livenessPassed: false), .match)
        for invalid: Float in [.nan, .infinity, -.infinity, 1.1, -1.1] {
            XCTAssertNotEqual(config.decision(scores: [0.9, invalid, 0.9], livenessPassed: true), .match)
        }
        XCTAssertNotEqual(config.decision(scores: [], livenessPassed: true), .match)
    }

    func testInvalidConfigurationFailsClosedAndThresholdIsAdjustable() {
        var config = FaceVerificationConfiguration()
        config.matchThreshold = 0.85
        XCTAssertEqual(config.decision(scores: [0.8, 0.8, 0.8], livenessPassed: true), .noMatch)
        config.matchThreshold = .nan
        XCTAssertFalse(config.isValid)
        XCTAssertNotEqual(config.decision(scores: [1, 1, 1], livenessPassed: true), .match)
        config.matchThreshold = 0.99
        XCTAssertFalse(config.isValid)
        config.matchThreshold = 0.55
        config.requiredSamples = 0
        XCTAssertFalse(config.isValid)
    }

    func testReceiptIsBoundToBothPhotoIDAndExactContents() {
        let id = UUID()
        let data = Data([1, 2, 3])
        let receipt = PhotoVerificationReceipt(photoID: id, imageData: data, outcome: .match)
        XCTAssertTrue(receipt.belongs(to: id, imageData: data))
        XCTAssertFalse(receipt.belongs(to: UUID(), imageData: data))
        XCTAssertFalse(receipt.belongs(to: id, imageData: Data([1, 2, 4])))
    }

    func testOnboardingRejectsUnverifiedPhotoAndRevalidatesReorderingAndReplacement() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .photos
        let first = ProfilePhoto(imageData: Data([1]), order: 0)
        let second = ProfilePhoto(imageData: Data([2]), order: 1)
        viewModel.draft.photos = [first, second]
        XCTAssertFalse(viewModel.canContinue)
        for outcome: FaceVerificationOutcome in [.noMatch, .failed("Cancelled")] {
            viewModel.recordPhotoVerification(.init(photoID: first.id, imageData: first.imageData, outcome: outcome))
            XCTAssertFalse(viewModel.canContinue)
        }
        viewModel.recordPhotoVerification(.init(photoID: first.id, imageData: first.imageData, outcome: .match))
        XCTAssertTrue(viewModel.canContinue)
        viewModel.movePhoto(from: IndexSet(integer: 1), to: 0)
        XCTAssertFalse(viewModel.canContinue)
        // A delayed completion for the old main photo cannot verify the new one.
        viewModel.recordPhotoVerification(.init(photoID: first.id, imageData: first.imageData, outcome: .match))
        XCTAssertFalse(viewModel.canContinue)
        viewModel.recordPhotoVerification(.init(photoID: second.id, imageData: second.imageData, outcome: .match))
        XCTAssertTrue(viewModel.canContinue)
        viewModel.draft.photos[0].imageData = Data([3])
        XCTAssertFalse(viewModel.canContinue)
        viewModel.removePhoto(id: second.id)
        XCTAssertFalse(viewModel.canContinue)
    }

    func testEmbeddingsRejectInvalidValuesAndCompareNormalizedVectors() throws {
        XCTAssertEqual(try SFaceEmbeddingModel.cosine([3, 4], [6, 8]), 1, accuracy: 0.00001)
        XCTAssertEqual(try SFaceEmbeddingModel.cosine([1, 0], [0, 1]), 0, accuracy: 0.00001)
        XCTAssertThrowsError(try SFaceEmbeddingModel.cosine([1], [1, 2]))
        XCTAssertThrowsError(try SFaceEmbeddingModel.normalized([0, 0]))
        XCTAssertThrowsError(try SFaceEmbeddingModel.normalized([.nan, 1]))
        XCTAssertThrowsError(try SFaceEmbeddingModel.normalized([]))
    }

    func testAlignmentFitsKnownRotationScaleAndTranslationWithoutMirroring() throws {
        let transform = CGAffineTransform(a: 0, b: 2, c: -2, d: 0, tx: 20, ty: 30)
        let source = [CGPoint(x: 1, y: 1), CGPoint(x: 4, y: 2), CGPoint(x: 2, y: 5)]
        let target = source.map { $0.applying(transform) }
        let actual = try FaceAlignment.similarityTransform(from: source, to: target)
        for (point, expected) in zip(source, target) {
            XCTAssertEqual(point.applying(actual).x, expected.x, accuracy: 0.00001)
            XCTAssertEqual(point.applying(actual).y, expected.y, accuracy: 0.00001)
        }
        XCTAssertThrowsError(try FaceAlignment.similarityTransform(from: [.zero, .zero], to: [.zero, .zero]))
        XCTAssertThrowsError(try FaceAlignment.similarityTransform(from: [], to: []))
    }

    func testBundledSFaceModelProducesFiniteNormalized128DimensionalEmbeddings() throws {
        let model = try SFaceEmbeddingModel(bundle: Bundle(for: OnboardingViewModel.self))
        let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 112, height: 112))
        let embedding = try model.embedding(alignedImage: image)
        XCTAssertEqual(embedding.count, 128)
        XCTAssertTrue(embedding.allSatisfy(\.isFinite))
        XCTAssertEqual(embedding.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
        XCTAssertEqual(try SFaceEmbeddingModel.cosine(embedding, model.embedding(alignedImage: image)), 1, accuracy: 0.0001)
    }

    func testModelInputUsesTopToBottomRGBPixelsInOriginal255Scale() throws {
        let model = try SFaceEmbeddingModel(bundle: Bundle(for: OnboardingViewModel.self))
        let top = CIImage(color: CIColor(red: 0, green: 1, blue: 0))
            .cropped(to: CGRect(x: 0, y: 56, width: 112, height: 56))
        let bottom = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 112, height: 56))
        let tensor = try model.inputTensor(for: top.composited(over: bottom))
        XCTAssertEqual(tensor[[0, 0, 0, 0]].floatValue, 0)
        XCTAssertEqual(tensor[[0, 0, 0, 1]].floatValue, 255)
        XCTAssertEqual(tensor[[0, 0, 0, 2]].floatValue, 0)
        XCTAssertEqual(tensor[[0, 111, 0, 0]].floatValue, 255)
        XCTAssertEqual(tensor[[0, 111, 0, 1]].floatValue, 0)
    }

    func testInvalidReferenceFailsWithoutStartingCamera() async {
        let completed = expectation(description: "Invalid photo fails closed")
        let camera = FaceVerificationCamera(configuration: .init()) { update in
            if case .finished(let outcome) = update {
                XCTAssertEqual(outcome, .failed(FaceScanError.invalidPhoto.localizedDescription))
                completed.fulfill()
            }
        }
        camera.start(referenceData: Data([1, 2, 3]))
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertFalse(camera.session.isRunning)
        XCTAssertTrue(camera.session.inputs.isEmpty)
        XCTAssertTrue(camera.session.outputs.isEmpty)
    }

    func testCameraRotationRespectsDifferentSensorsAndIgnoresSmallHandMovements() {
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: 0), 0, "Some front sensors are already upright.")
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: 90), 90, "Other sensors need a quarter turn.")
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: 89.6), 90)
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: -0.4), 0)
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: -90), 270)
        XCTAssertEqual(FaceCameraRotation.quarterTurn(for: 450), 90)
        XCTAssertNil(FaceCameraRotation.quarterTurn(for: .nan))
    }

    func testNaturalHeadTiltAndWrappedRollDoNotRejectAnOtherwiseUsableFace() {
        func geometry(roll: Double, yaw: Double = 0) -> FaceCaptureGeometry {
            FaceCaptureGeometry(boundingBox: CGRect(x: 0.11, y: 0.15, width: 0.78, height: 0.58),
                                imageSize: CGSize(width: 720, height: 1280), confidence: 1,
                                roll: roll, yaw: yaw, hasLandmarks: true)
        }
        XCTAssertEqual(geometry(roll: 0).guidance, .ready)
        XCTAssertEqual(geometry(roll: .pi / 12).guidance, .ready, "15 degrees previously failed the arbitrary 0.25-radian cutoff.")
        XCTAssertEqual(geometry(roll: 2 * .pi - 0.1).guidance, .ready)
        XCTAssertEqual(geometry(roll: .pi / 2).guidance, .levelPhone, "A rotation error must not be called poor lighting.")
        XCTAssertEqual(geometry(roll: 0, yaw: .pi / 4).guidance, .ready, "A requested turn must not be rejected as bad framing.")
        XCTAssertEqual(geometry(roll: .nan).guidance, .levelPhone)
    }

    func testGeometryGivesSpecificDistanceAndFeatureGuidance() {
        func geometry(box: CGRect, hasLandmarks: Bool = true) -> FaceCaptureGeometry {
            FaceCaptureGeometry(boundingBox: box, imageSize: CGSize(width: 720, height: 1280),
                                confidence: 1, roll: 0, yaw: 0, hasLandmarks: hasLandmarks)
        }
        XCTAssertEqual(geometry(box: CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)).guidance, .moveCloser)
        XCTAssertEqual(geometry(box: CGRect(x: -0.1, y: 0, width: 1, height: 0.9)).guidance, .moveBack)
        XCTAssertEqual(geometry(box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), hasLandmarks: false).guidance, .showFeatures)
    }

    func testQualityBelowPointThreeOrMissingQualityDoesNotCauseAnEndlessRestart() {
        for quality: Float? in [0.282, nil] {
            var samples = FaceVerificationSamples()
            for frame in 0..<6 {
                samples.append(score: 0.8, quality: quality, at: Double(frame) * 0.2)
            }
            XCTAssertNil(samples.decision(configuration: .init(), livenessPassed: false, at: 1))
            XCTAssertEqual(samples.decision(configuration: .init(), livenessPassed: true, at: 1), .match)
            samples.reset()
            XCTAssertNil(samples.decision(configuration: .init(), livenessPassed: true, at: 2))
        }
    }

    func testQualityPreferenceNeverLowersIdentityThresholdOrAcceptsTooFewSamples() {
        var samples = FaceVerificationSamples()
        samples.append(score: 0.8, quality: 0.9, at: 0)
        samples.append(score: 0.8, quality: 0.9, at: 0.2)
        XCTAssertNil(samples.decision(configuration: .init(), livenessPassed: true, at: 1))
        samples.append(score: 0.59, quality: 0.9, at: 0.4)
        XCTAssertEqual(samples.decision(configuration: .init(), livenessPassed: true, at: 1), .noMatch)
        var configuration = FaceVerificationConfiguration()
        configuration.requiredSamples = 6
        XCTAssertNil(samples.decision(configuration: configuration, livenessPassed: true, at: 1))
    }

    func testSharedFrameAnalyzerRejectsImagesWithoutAFace() throws {
        let image = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 720, height: 1280))
        let raster = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        XCTAssertThrowsError(try FaceFrameAnalyzer().analyze(CIImage(cgImage: raster))) { error in
            XCTAssertEqual(error as? FaceScanError, .faceCount, "Unexpected Vision error: \(error)")
        }
    }
}
