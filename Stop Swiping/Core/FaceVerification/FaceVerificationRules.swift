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
