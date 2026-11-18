import CoreGraphics
import XCTest
@testable import Stop_Swiping

@MainActor
final class FaceCircleScanTests: XCTestCase {
    private let neutral = FaceHeadPose(horizontal: 0, vertical: -0.5, yaw: 0)

    private func start(clockwise: Bool = true) -> FaceScanProgress {
        var scan = FaceScanProgress(configuration: .init(), clockwise: clockwise)
        for frame in 0..<3 {
            scan.accept(pose: neutral, identityScore: 0.85, quality: 0.5, at: Double(frame) * 0.2)
        }
        XCTAssertEqual(scan.snapshot.phase, .circling)
        return scan
    }

    private func pose(sector: Int) -> FaceHeadPose {
        let angle = Double(sector) * .pi / 4
        return FaceHeadPose(horizontal: 0.18 * sin(angle), vertical: -0.5 - 0.12 * cos(angle), yaw: 0.4 * sin(angle))
    }

    private func collectNext(_ scan: inout FaceScanProgress, time: inout Double) {
        let target = scan.snapshot.targetSector!
        for _ in 0..<2 {
            scan.accept(pose: pose(sector: target), identityScore: nil, quality: 0.2, at: time)
            time += 0.2
        }
    }

    private func fullCircle(clockwise: Bool = true) -> (FaceScanProgress, Double) {
        var scan = start(clockwise: clockwise)
        var time = 0.6
        for index in 0..<8 {
            collectNext(&scan, time: &time)
            XCTAssertEqual(scan.snapshot.collectedSectors.count, index + 1)
        }
        XCTAssertEqual(scan.snapshot.phase, .finishing)
        XCTAssertNil(scan.outcome, "Lighting the ring must never itself verify identity.")
        return (scan, time)
    }

    func testFullCameraSequenceInBothDirectionsRequiresFinalIdentityMatch() {
        for clockwise in [true, false] {
            var (scan, time) = fullCircle(clockwise: clockwise)
            for _ in 0..<4 {
                scan.accept(pose: neutral, identityScore: 0.85, quality: 0.5, at: time)
                time += 0.2
            }
            XCTAssertEqual(scan.outcome, .match)
            XCTAssertEqual(scan.snapshot.progress, 1)
        }
    }

    func testProgressSurvivesSlowContinuousTransitionThatPreviouslyResetAfterOneSide() {
        var scan = start()
        var time = 0.6
        collectNext(&scan, time: &time)
        let collected = scan.snapshot.collectedSectors
        // More than the old 1.25-second pose timeout, but with a usable face
        // arriving continuously. Returning to center must not erase any ticks.
        for _ in 0..<20 {
            scan.accept(pose: neutral, identityScore: nil, quality: 0.2, at: time)
            time += 0.2
            XCTAssertEqual(scan.snapshot.collectedSectors, collected)
            XCTAssertNil(scan.outcome)
        }
        collectNext(&scan, time: &time)
        XCTAssertEqual(scan.snapshot.collectedSectors.count, 2)
    }

    func testBriefMissingFaceKeepsCollectedTicksAndResumesAtSameTarget() {
        var scan = start()
        var time = 0.6
        collectNext(&scan, time: &time)
        let collected = scan.snapshot.collectedSectors
        let target = scan.snapshot.targetSector
        scan.pause(message: "Face briefly hidden", at: time)
        time += 0.8
        XCTAssertEqual(scan.snapshot.collectedSectors, collected)
        XCTAssertEqual(scan.snapshot.targetSector, target)
        collectNext(&scan, time: &time)
        XCTAssertEqual(scan.snapshot.collectedSectors.count, 2)
        XCTAssertNil(scan.outcome)
    }

    func testLongFaceLossFailsExplicitlyWithoutSilentlyClearingTheRing() {
        var scan = start()
        var time = 0.6
        collectNext(&scan, time: &time)
        let collected = scan.snapshot.collectedSectors
        scan.pause(message: "Face lost", at: time + 3)
        guard case .failed = scan.outcome else { return XCTFail("Long face loss must end this attempt.") }
        XCTAssertEqual(scan.snapshot.collectedSectors, collected)
        scan.accept(pose: neutral, identityScore: 0.9, quality: 0.9, at: time + 3.2)
        XCTAssertNotEqual(scan.outcome, .match)
    }

    func testStaticFaceCannotCollectTheRingEvenWithHighSimilarity() {
        var scan = start()
        for frame in 0..<100 {
            scan.accept(pose: neutral, identityScore: 0.99, quality: 0.9, at: 0.6 + Double(frame) * 0.2)
        }
        XCTAssertTrue(scan.snapshot.collectedSectors.isEmpty)
        XCTAssertNil(scan.outcome)
    }

    func testWrongDirectionAndOneFrameCannotCollectExtraAreas() {
        var scan = start()
        scan.accept(pose: pose(sector: 4), identityScore: nil, quality: nil, at: 0.6)
        scan.accept(pose: pose(sector: 4), identityScore: nil, quality: nil, at: 0.8)
        XCTAssertTrue(scan.snapshot.collectedSectors.isEmpty)
        scan.accept(pose: pose(sector: 0), identityScore: nil, quality: nil, at: 1)
        XCTAssertTrue(scan.snapshot.collectedSectors.isEmpty)
        scan.accept(pose: pose(sector: 0), identityScore: nil, quality: nil, at: 1.2)
        // Filtering a 180-degree jump passes through the neutral dead zone;
        // wait for the second usable top observation rather than counting it.
        XCTAssertTrue(scan.snapshot.collectedSectors.isEmpty)
        scan.accept(pose: pose(sector: 0), identityScore: nil, quality: nil, at: 1.4)
        XCTAssertEqual(scan.snapshot.collectedSectors, [0])
    }

    func testUncertainFinalIdentityCannotMatchOrResetCompletedMovement() {
        var (scan, time) = fullCircle()
        for _ in 0..<4 {
            scan.accept(pose: neutral, identityScore: 0.59, quality: 0.9, at: time)
            time += 0.25
        }
        XCTAssertEqual(scan.outcome, .noMatch)
        XCTAssertEqual(scan.snapshot.progress, 1)
    }

    func testTransientUncertainFrameRetainsRingAndCanRecoverWithValidFinalSamples() {
        var (scan, time) = fullCircle()
        scan.accept(pose: neutral, identityScore: 0.59, quality: 0.9, at: time)
        XCTAssertNil(scan.outcome)
        XCTAssertEqual(scan.snapshot.progress, 1)
        for _ in 0..<4 {
            time += 0.2
            scan.accept(pose: neutral, identityScore: 0.85, quality: 0.5, at: time)
        }
        XCTAssertEqual(scan.outcome, .match)
    }

    func testACompletedCircleStillRequiresReturningToNeutral() {
        var (scan, time) = fullCircle()
        for _ in 0..<6 {
            scan.accept(pose: pose(sector: 2), identityScore: 0.99, quality: 0.9, at: time)
            time += 0.2
        }
        XCTAssertNil(scan.outcome)
        XCTAssertEqual(scan.snapshot.phase, .finishing)
    }

    func testMissingInitialIdentityCannotBeginCollection() {
        var scan = FaceScanProgress(configuration: .init())
        for frame in 0..<10 {
            scan.accept(pose: neutral, identityScore: nil, quality: 0.9, at: Double(frame) * 0.2)
        }
        XCTAssertEqual(scan.snapshot.phase, .positioning)
        XCTAssertTrue(scan.snapshot.collectedSectors.isEmpty)
    }

    func testBackwardsTimestampFailsWithoutErasingProgress() {
        var scan = start()
        var time = 0.6
        collectNext(&scan, time: &time)
        scan.accept(pose: neutral, identityScore: nil, quality: nil, at: 0.2)
        guard case .failed = scan.outcome else { return XCTFail("Out-of-order frames must fail closed.") }
        XCTAssertEqual(scan.snapshot.collectedSectors.count, 1)
    }

    func testHeadPoseIgnoresTranslationScalingAndInPlaneRotation() throws {
        let eyes = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)]
        let nose = CGPoint(x: 1, y: -0.8), mouth = CGPoint(x: 1, y: -2)
        let original = try XCTUnwrap(FaceHeadPose.estimate(eyeA: eyes[0], eyeB: eyes[1], nose: nose, mouth: mouth, yaw: 0))
        let transform = CGAffineTransform(rotationAngle: 0.3).scaledBy(x: 4, y: 4).translatedBy(x: 23, y: 9)
        let moved = try XCTUnwrap(FaceHeadPose.estimate(eyeA: eyes[0].applying(transform), eyeB: eyes[1].applying(transform),
                                                     nose: nose.applying(transform), mouth: mouth.applying(transform), yaw: 0))
        XCTAssertEqual(original.horizontal, moved.horizontal, accuracy: 0.00001)
        XCTAssertEqual(original.vertical, moved.vertical, accuracy: 0.00001)
        XCTAssertNil(FaceHeadPose.estimate(eyeA: .zero, eyeB: .zero, nose: nose, mouth: mouth, yaw: 0))
    }

    func testDelayedCameraUpdatesCannotRollBackDisplayedProgress() {
        let current = FaceScanSnapshot(phase: .circling, collectedSectors: [0, 1], targetSector: 2)
        XCTAssertFalse(FaceScanSnapshot(phase: .circling, collectedSectors: [0]).canReplace(current))
        XCTAssertFalse(FaceScanSnapshot(phase: .positioning).canReplace(current))
        XCTAssertTrue(FaceScanSnapshot(phase: .circling, collectedSectors: [0, 1, 2]).canReplace(current))
        XCTAssertFalse(FaceScanSnapshot(phase: .circling, collectedSectors: Set(0..<8))
            .canReplace(FaceScanSnapshot(phase: .finishing, collectedSectors: Set(0..<8))))
    }

    func testContinuousSweepCollectsRingWithoutStoppingOnEachBall() {
        for clockwise in [true, false] {
            var circle = FaceCircleChallenge(clockwise: clockwise)
            let sign = clockwise ? 1.0 : -1.0
            // Thirty degrees per camera frame: no sample is held at a target.
            for frame in 0...12 {
                let angle = sign * Double(frame) * .pi / 6
                circle.observe(motion: CGPoint(x: sin(angle), y: -cos(angle)), at: Double(frame) * 0.16)
            }
            XCTAssertTrue(circle.isComplete)
        }
    }

    func testLastLeftSegmentAcceptsNaturalDownwardDriftInsteadOfStallingAt75Percent() {
        var circle = FaceCircleChallenge(clockwise: true)
        var time = 0.0
        for sector in 0..<6 {
            let angle = Double(sector) * .pi / 4
            for _ in 0..<2 {
                circle.observe(motion: CGPoint(x: sin(angle), y: -cos(angle)), at: time)
                time += 0.2
            }
        }
        XCTAssertEqual(circle.collected.count, 6)
        XCTAssertEqual(circle.targetSector, 6)
        // About 34 degrees below left, outside the old narrow acceptance cone.
        for _ in 0..<3 {
            circle.observe(motion: CGPoint(x: -0.9, y: 0.6), at: time)
            time += 0.2
        }
        XCTAssertTrue(circle.collected.contains(6))
    }

    func testCursorCanReachTheTargetOrbitWithASmallMovement() {
        let cursor = FaceCircleChallenge.visualCursor(for: CGPoint(x: -0.55, y: 0))
        XCTAssertEqual(cursor.x, -1, accuracy: 0.00001)
        XCTAssertEqual(cursor.y, 0, accuracy: 0.00001)
        XCTAssertEqual(FaceCircleChallenge.visualCursor(for: .zero), .zero)
    }

    func testProductionFlowRecoversFrom75PercentWithANaturalLowLeftPose() {
        var scan = start()
        var time = 0.6
        for _ in 0..<6 { collectNext(&scan, time: &time) }
        XCTAssertEqual(scan.snapshot.progress, 0.75)
        let slightlyLowLeft = FaceHeadPose(horizontal: -0.126, vertical: -0.44, yaw: -0.3)
        for _ in 0..<4 {
            scan.accept(pose: slightlyLowLeft, identityScore: nil, quality: 0.3, at: time)
            time += 0.2
        }
        XCTAssertTrue(scan.snapshot.collectedSectors.contains(6))
        XCTAssertNil(scan.outcome)
    }

    func testStationaryOffsetAndLargeJumpsCannotFillTheRing() {
        var circle = FaceCircleChallenge(clockwise: true)
        for frame in 0..<30 {
            circle.observe(motion: CGPoint(x: 0, y: -1), at: Double(frame) * 0.16)
        }
        XCTAssertEqual(circle.collected, [0])
        circle.observe(motion: CGPoint(x: 0, y: 1), at: 5)
        XCTAssertEqual(circle.collected, [0])
    }
}
