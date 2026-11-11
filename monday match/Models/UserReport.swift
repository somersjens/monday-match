import Foundation

struct UserReport: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let reason: String
    let details: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        matchID: UUID,
        reason: String,
        details: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.matchID = matchID
        self.reason = reason
        self.details = details
        self.createdAt = createdAt
    }
}
