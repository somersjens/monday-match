import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Sender: String, Codable {
        case currentUser
        case match
        case system
    }

    let id: UUID
    let sender: Sender
    let text: String
    let sentAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        sender: Sender,
        text: String,
        sentAt: Date = Date(),
        isRead: Bool = true
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.sentAt = sentAt
        self.isRead = isRead
    }
}
