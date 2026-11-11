import Foundation

struct MatchResult: Equatable, Identifiable {
    enum Outcome: Equatable {
        case noMatch
        case matched(MatchedProfile)
    }

    let id: UUID
    let revealedAt: Date
    let compatibilityScore: Int?
    let outcome: Outcome

    init(
        id: UUID = UUID(),
        revealedAt: Date,
        compatibilityScore: Int?,
        outcome: Outcome
    ) {
        self.id = id
        self.revealedAt = revealedAt
        self.compatibilityScore = compatibilityScore
        self.outcome = outcome
    }

    static let noMatchMock = MatchResult(
        revealedAt: Date(),
        compatibilityScore: nil,
        outcome: .noMatch
    )

    static let successfulMock = MatchResult(
        revealedAt: Date(),
        compatibilityScore: 78,
        outcome: .matched(.mock)
    )
}
