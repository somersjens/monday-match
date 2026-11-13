import CryptoKit
import Foundation

nonisolated enum FaceVerificationOutcome: Equatable, Sendable {
    case match
    case noMatch
    case failed(String)

    var title: String {
        switch self {
        case .match: L10n("Match")
        case .noMatch: L10n("No match")
        case .failed: L10n("Verification failed")
        }
    }

    var message: String {
        switch self {
        case .match: L10n("Your live scan matches this photo.")
        case .noMatch: L10n("We couldn’t confirm that this is you. Choose a clearer photo or try again.")
        case .failed(let reason): reason
        }
    }
}

/// Only an in-memory result; never encode this or add it to a profile/upload.
nonisolated struct PhotoVerificationReceipt: Equatable, Sendable {
    let photoID: UUID
    let photoDigest: Data
    let outcome: FaceVerificationOutcome

    init(photoID: UUID, imageData: Data, outcome: FaceVerificationOutcome) {
        self.photoID = photoID
        photoDigest = Data(SHA256.hash(data: imageData))
        self.outcome = outcome
    }

    func belongs(to photoID: UUID, imageData: Data) -> Bool {
        self.photoID == photoID && photoDigest == Data(SHA256.hash(data: imageData))
    }
}

/// SFace cosine similarity, not a probability. Tune against a representative
/// validation set before release; never expose this as an end-user preference.
nonisolated struct FaceVerificationConfiguration: Sendable {
    var matchThreshold: Float = 0.55
    var uncertaintyMargin: Float = 0.05
    // Vision's score ranks captures of the same face; it is not an absolute
    // lighting/identity test. Prefer these frames, but never restart on a blink.
    var preferredCaptureQuality: Float = 0.3
    var timeout: TimeInterval = 45
    var maximumFaceGap: TimeInterval = 2.5
    var requiredSamples = 3

    var isValid: Bool {
        matchThreshold.isFinite && uncertaintyMargin.isFinite
            && (0...1).contains(matchThreshold) && uncertaintyMargin >= 0
            && matchThreshold + uncertaintyMargin <= 1
            && preferredCaptureQuality.isFinite && (0...1).contains(preferredCaptureQuality)
            && timeout.isFinite && timeout > 0
            && maximumFaceGap.isFinite && maximumFaceGap > 0
            && (3...30).contains(requiredSamples)
    }

    func decision(scores: [Float], livenessPassed: Bool) -> FaceVerificationOutcome {
        guard isValid, livenessPassed, scores.count >= requiredSamples,
              scores.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
            return .failed(L10n("The scan was incomplete. Please try again."))
        }
        guard scores.allSatisfy({ $0 >= matchThreshold + uncertaintyMargin }) else {
            return .noMatch
        }
        return .match
    }
}

/// Select the best *matched* final captures. The quality preference is bounded:
/// an otherwise valid face scoring 0.28 must not loop forever below a 0.30 goal.
nonisolated struct FaceVerificationSamples {
    private struct Sample {
        let score: Float
        let quality: Float
    }
    private var samples: [Sample] = []
    private var startedAt: TimeInterval?

    mutating func reset() {
        samples.removeAll(keepingCapacity: false)
        startedAt = nil
    }

    mutating func append(score: Float, quality: Float?, at timestamp: TimeInterval) {
        guard score.isFinite, (-1...1).contains(score), timestamp.isFinite else { return }
        if startedAt == nil { startedAt = timestamp }
        let rank = quality.flatMap { $0.isFinite ? $0 : nil } ?? 0
        samples.append(Sample(score: score, quality: rank))
        // Only retain the best captures, not an unbounded biometric history.
        samples.sort { $0.quality > $1.quality }
        if samples.count > 30 { samples.removeLast(samples.count - 30) }
    }

    func decision(configuration: FaceVerificationConfiguration, livenessPassed: Bool,
                  at timestamp: TimeInterval) -> FaceVerificationOutcome? {
        guard configuration.isValid else {
            return configuration.decision(scores: [], livenessPassed: livenessPassed)
        }
        guard livenessPassed, let startedAt, samples.count >= configuration.requiredSamples else { return nil }
        let preferred = samples.filter { $0.quality >= configuration.preferredCaptureQuality }
        guard preferred.count >= configuration.requiredSamples || timestamp - startedAt >= 0.8 else { return nil }
        return configuration.decision(scores: Array(samples.prefix(configuration.requiredSamples)).map(\.score),
                                      livenessPassed: livenessPassed)
    }
}
