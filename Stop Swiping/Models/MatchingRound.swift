import Foundation

struct MatchingRound: Equatable, Identifiable {
    enum Status: String, Equatable {
        case open
        case locked
        case matching
        case revealed
    }

    let id: UUID
    let opensAt: Date
    let profileDeadline: Date
    let locksAt: Date
    let revealAt: Date
    var status: Status

    init(
        id: UUID = UUID(),
        opensAt: Date,
        profileDeadline: Date,
        locksAt: Date,
        revealAt: Date,
        status: Status
    ) {
        self.id = id
        self.opensAt = opensAt
        self.profileDeadline = profileDeadline
        self.locksAt = locksAt
        self.revealAt = revealAt
        self.status = status
    }
}
