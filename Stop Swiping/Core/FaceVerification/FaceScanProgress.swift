import CoreGraphics
import Foundation

/// Translation/scale/roll-invariant nose position relative to eyes and mouth.
/// Unlike VNFaceObservation.pitch, these landmarks are available on the Vision
/// request revisions used by the app. Coordinates match the mirrored preview.
nonisolated struct FaceHeadPose: Sendable {
    let horizontal: Double
    let vertical: Double
    let yaw: Double

    static func estimate(eyeA: CGPoint, eyeB: CGPoint, nose: CGPoint, mouth: CGPoint,
                         yaw: Double) -> FaceHeadPose? {
        let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
        let dx = eyes[1].x - eyes[0].x, dy = eyes[1].y - eyes[0].y
        let distance = hypot(dx, dy)
        guard distance > 0.0001, distance.isFinite, yaw.isFinite else { return nil }
        let mid = CGPoint(x: (eyeA.x + eyeB.x) / 2, y: (eyeA.y + eyeB.y) / 2)
        let ux = dx / distance, uy = dy / distance
        func project(_ point: CGPoint) -> CGPoint {
            let x = point.x - mid.x, y = point.y - mid.y
            return CGPoint(x: (x * ux + y * uy) / distance, y: (-x * uy + y * ux) / distance)
        }
        let tip = project(nose), lips = project(mouth)
        guard abs(lips.y) > 0.1 else { return nil }
        let horizontal = -Double(tip.x)
        let vertical = -Double((tip.y - lips.y) / -lips.y)
        guard horizontal.isFinite, vertical.isFinite else { return nil }
        return FaceHeadPose(horizontal: horizontal, vertical: vertical, yaw: yaw)
    }
}

nonisolated enum FaceScanPhase: Int, Sendable {
    case positioning, circling, finishing
}

nonisolated struct FaceScanSnapshot: Sendable {
    var phase: FaceScanPhase = .positioning
    var collectedSectors: Set<Int> = []
    var targetSector: Int?
    var cursor: CGPoint?
    var clockwise = true
    var instruction = L10n("Look at the camera")

    var progress: Double { Double(collectedSectors.count) / Double(FaceCircleChallenge.sectorCount) }

    func canReplace(_ previous: FaceScanSnapshot) -> Bool {
        phase.rawValue >= previous.phase.rawValue && collectedSectors.isSuperset(of: previous.collectedSectors)
    }
}

/// Every tick corresponds to observed head movement, never a timer animation.
/// Small misses pause collection; collected sectors are only cleared by a new
/// explicit attempt. Circle direction is randomized per attempt.
nonisolated struct FaceCircleChallenge: Sendable {
    static let sectorCount = 8
    let clockwise: Bool
    private(set) var collected: Set<Int> = []
    static let minimumRadius: CGFloat = 0.5
    static let angularTolerance: Double = .pi * 2 / 9 // 40°, including natural vertical drift.
    private var previous: (motion: CGPoint, timestamp: TimeInterval)?

    init(clockwise: Bool = Bool.random()) { self.clockwise = clockwise }
    var isComplete: Bool { collected.count == Self.sectorCount }
    var targetSector: Int? {
        guard !isComplete else { return nil }
        return clockwise ? collected.count : (Self.sectorCount - collected.count) % Self.sectorCount
    }

    mutating func pause() { previous = nil }

    /// Target and measured cursor use the same orbit. The former UI kept the
    /// cursor permanently inside the target, making the balls impossible to meet.
    static func visualCursor(for motion: CGPoint) -> CGPoint {
        let radius = hypot(motion.x, motion.y)
        guard radius.isFinite, radius > 0 else { return .zero }
        let divisor = max(minimumRadius, radius)
        return CGPoint(x: motion.x / divisor, y: motion.y / divisor)
    }

    mutating func observe(motion: CGPoint, at timestamp: TimeInterval) {
        guard !isComplete, timestamp.isFinite, motion.x.isFinite, motion.y.isFinite else { return }
        let radius = hypot(motion.x, motion.y)
        guard radius >= Self.minimumRadius, radius <= 4 else { pause(); return }
        defer { previous = (motion, timestamp) }
        guard let previous else { return }
        let elapsed = timestamp - previous.timestamp
        guard elapsed >= 0.06, elapsed <= 0.5 else { return }
        let angle = atan2(motion.y, motion.x) + .pi / 2
        let before = atan2(previous.motion.y, previous.motion.x) + .pi / 2
        func wrapped(_ value: Double) -> Double { atan2(sin(value), cos(value)) }
        let turn = wrapped(angle - before)
        // Reject jumps; interpolate only small, observed continuous sweeps.
        guard abs(turn) <= .pi / 2 + 0.1 else { return }
        let direction = clockwise ? 1.0 : -1.0
        let travel = direction * turn
        func crossed(_ target: Double) -> Bool {
            let distance = (direction * (target - before) + 4 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            return travel > 0.02 && distance <= travel + 0.00001
        }
        var captures = 0
        while let targetSector, captures < 2 {
            let target = Double(targetSector) * 2 * .pi / Double(Self.sectorCount)
            let near = abs(wrapped(angle - target)) <= Self.angularTolerance
                && abs(wrapped(before - target)) <= Self.angularTolerance
            // No stop/hold required: passing through the target between two
            // camera frames is valid evidence, even when neither lands on it.
            guard crossed(target) || (captures == 0 && near) else { break }
            collected.insert(targetSector)
            captures += 1
        }
    }
}

/// The actual camera state machine. Tests feed complete frame sequences into
/// this type, including the transitions that previously reset during a turn.
nonisolated struct FaceScanProgress {
    private(set) var snapshot = FaceScanSnapshot()
    private(set) var outcome: FaceVerificationOutcome?
    private let configuration: FaceVerificationConfiguration
    private var circle: FaceCircleChallenge
    private var baseline: FaceHeadPose?
    private var filteredMotion: CGPoint?
    private var neutralPoses: [FaceHeadPose] = []
    private var neutralSince: TimeInterval?
    private var samples = FaceVerificationSamples()
    private var lastFaceTime: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var mismatchSince: TimeInterval?
    private var mismatches = 0

    init(configuration: FaceVerificationConfiguration, clockwise: Bool = Bool.random()) {
        self.configuration = configuration
        circle = FaceCircleChallenge(clockwise: clockwise)
        snapshot.clockwise = clockwise
    }

    var needsIdentity: Bool { snapshot.phase != .circling }

    private func motion(for pose: FaceHeadPose) -> CGPoint {
        guard let baseline else { return .zero }
        return CGPoint(x: (pose.horizontal - baseline.horizontal) / 0.14,
                       y: (pose.vertical - baseline.vertical) / 0.10)
    }

    mutating func accept(pose: FaceHeadPose, identityScore: Float?, quality: Float?, at timestamp: TimeInterval) {
        guard outcome == nil, timestamp.isFinite else { return }
        guard configuration.isValid else { outcome = .failed(L10n("The scan settings are invalid.")); return }
        if let lastTimestamp, timestamp <= lastTimestamp {
            outcome = .failed(L10n("The camera stream was interrupted. Please start a new scan."))
            return
        }
        lastTimestamp = timestamp
        if let lastFaceTime, timestamp - lastFaceTime > configuration.maximumFaceGap {
            outcome = .failed(L10n("Your face was out of view for too long. Please start a new scan."))
            return
        }
        lastFaceTime = timestamp
        guard pose.horizontal.isFinite, pose.vertical.isFinite, pose.yaw.isFinite else {
            pause(message: L10n("Keep your eyes, nose and mouth visible."), at: timestamp)
            return
        }

        switch snapshot.phase {
        case .positioning:
            guard abs(pose.yaw) <= 0.35 else {
                neutralPoses.removeAll(); neutralSince = nil
                snapshot.instruction = L10n("Look at the camera")
                return
            }
            guard acceptsIdentity(identityScore, at: timestamp) else { return }
            if let first = neutralPoses.first,
               hypot(pose.horizontal - first.horizontal, pose.vertical - first.vertical) > 0.09 {
                neutralPoses.removeAll(); neutralSince = nil
            }
            if neutralSince == nil { neutralSince = timestamp }
            neutralPoses.append(pose)
            if let neutralSince, neutralPoses.count >= 3, timestamp - neutralSince >= 0.35 {
                baseline = FaceHeadPose(horizontal: neutralPoses.map(\.horizontal).reduce(0, +) / Double(neutralPoses.count),
                                        vertical: neutralPoses.map(\.vertical).reduce(0, +) / Double(neutralPoses.count), yaw: pose.yaw)
                neutralPoses.removeAll()
                snapshot.phase = .circling
                snapshot.targetSector = circle.targetSector
                snapshot.instruction = L10n("Follow the ball with your head")
            }
        case .circling:
            let measured = motion(for: pose)
            let motion = filteredMotion.map {
                CGPoint(x: $0.x * 0.3 + measured.x * 0.7, y: $0.y * 0.3 + measured.y * 0.7)
            } ?? measured
            filteredMotion = motion
            snapshot.cursor = motion
            circle.observe(motion: motion, at: timestamp)
            snapshot.collectedSectors = circle.collected
            snapshot.targetSector = circle.targetSector
            snapshot.instruction = L10n("Follow the ball with your head")
            if circle.isComplete {
                snapshot.phase = .finishing
                samples.reset()
                snapshot.instruction = L10n("Look at the camera")
            }
        case .finishing:
            let motion = motion(for: pose)
            snapshot.cursor = motion
            guard hypot(motion.x, motion.y) <= 0.7, abs(pose.yaw) <= 0.35 else {
                samples.reset()
                snapshot.instruction = L10n("Look at the camera")
                return
            }
            guard acceptsIdentity(identityScore, at: timestamp), let identityScore else { samples.reset(); return }
            samples.append(score: identityScore, quality: quality, at: timestamp)
            snapshot.instruction = L10n("Checking…")
            outcome = samples.decision(configuration: configuration, livenessPassed: circle.isComplete, at: timestamp)
        }
    }

    private mutating func acceptsIdentity(_ score: Float?, at timestamp: TimeInterval) -> Bool {
        guard let score, score.isFinite, (-1...1).contains(score) else {
            snapshot.instruction = L10n("Look at the camera")
            return false
        }
        guard score >= configuration.matchThreshold + configuration.uncertaintyMargin else {
            if mismatchSince == nil { mismatchSince = timestamp }
            mismatches += 1
            if let mismatchSince, mismatches >= configuration.requiredSamples, timestamp - mismatchSince >= 0.4 {
                outcome = .noMatch
            }
            snapshot.instruction = L10n("Relax and look at the camera")
            return false
        }
        mismatchSince = nil; mismatches = 0
        return true
    }

    mutating func pause(message: String, at timestamp: TimeInterval) {
        guard outcome == nil else { return }
        circle.pause()
        filteredMotion = nil
        samples.reset()
        neutralPoses.removeAll(); neutralSince = nil
        snapshot.cursor = nil
        snapshot.instruction = message
        if let lastFaceTime, timestamp - lastFaceTime > configuration.maximumFaceGap {
            outcome = .failed(L10n("Your face was out of view for too long. Please start a new scan."))
        }
    }
}
