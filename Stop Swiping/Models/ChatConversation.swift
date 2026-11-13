import Foundation

struct ChatConversation: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let participantName: String
    var messages: [ChatMessage]
    var isBlocked: Bool
    var isClosed: Bool

    init(
        id: UUID = UUID(),
        matchID: UUID,
        participantName: String,
        messages: [ChatMessage],
        isBlocked: Bool = false,
        isClosed: Bool = false
    ) {
        self.id = id
        self.matchID = matchID
        self.participantName = participantName
        self.messages = messages
        self.isBlocked = isBlocked
        self.isClosed = isClosed
    }

    static func mock(
        matchID: UUID = MatchedProfile.mock.id
    ) -> ChatConversation {
        ChatConversation(
            matchID: matchID,
            participantName: "Alex",
            messages: [
                ChatMessage(
                    sender: .system,
                    text: "You matched. Be kind, curious and respectful.",
                    sentAt: Date().addingTimeInterval(-3_600)
                ),
                ChatMessage(
                    sender: .match,
                    text: "Hi Sam! I saw you like cooking too. What's your go-to dinner for friends?",
                    sentAt: Date().addingTimeInterval(-2_400)
                )
            ]
        )
    }
}
