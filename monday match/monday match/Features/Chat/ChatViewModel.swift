import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversation: ChatConversation
    @Published var draftMessage = ""
    @Published var showsBlockConfirmation = false
    @Published var showsReportSheet = false
    @Published private(set) var lastReport: UserReport?

    init(
        conversation: ChatConversation
    ) {
        self.conversation = conversation
    }

    var canSend: Bool {
        !conversation.isBlocked &&
        !conversation.isClosed &&
        !draftMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func sendMessage() {
        let trimmed = draftMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard canSend, !trimmed.isEmpty else { return }

        conversation.messages.append(
            ChatMessage(
                sender: .currentUser,
                text: trimmed,
                sentAt: Date(),
                isRead: true
            )
        )

        draftMessage = ""
    }

    func blockMatch() {
        conversation.isBlocked = true
        conversation.isClosed = true

        conversation.messages.append(
            ChatMessage(
                sender: .system,
                text: "This match has been blocked. Messaging is disabled.",
                sentAt: Date()
            )
        )
    }

    func submitReport(
        reason: ReportReason,
        details: String
    ) {
        lastReport = UserReport(
            matchID: conversation.matchID,
            reason: reason.rawValue,
            details: details
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        showsReportSheet = false
    }
}
