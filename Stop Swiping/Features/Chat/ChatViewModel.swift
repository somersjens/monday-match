import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversation: ChatConversation
    @Published var draftMessage = ""
    @Published var showsBlockConfirmation = false
    @Published var showsEndConfirmation = false
    @Published var showsReportSheet = false
    @Published private(set) var lastReport: UserReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var securityCode: String?
    @Published private(set) var requiresKeyConfirmation = false
    @Published private(set) var requiresDeviceReplacement = false
    @Published private(set) var securityCodeVerified = false
    @Published private(set) var isReady = false
    @Published private(set) var pendingMessageCount = 0
    @Published private(set) var isPerformingAction = false
    /// Shown while the other person is writing; the demo fakes it.
    @Published private(set) var isPartnerTyping = false
    /// When the newest message the partner has read was sent.
    @Published var partnerReadAt: Date?
    /// The last message from the partner seen on this phone.
    @Published private(set) var lastReadAt: Date
    let secureSession: SecureChatSession?
    /// Before launch: every message gets this answer back.
    let autoReply: String?
    private let defaults: UserDefaults
    private var replyTask: Task<Void, Never>?
    var isLive: Bool { secureSession != nil }
    var isDemo: Bool { autoReply != nil }
    init(conversation: ChatConversation, secureSession: SecureChatSession? = nil,
         autoReply: String? = nil, defaults: UserDefaults = .standard) {
        self.conversation=conversation; self.secureSession=secureSession
        self.autoReply=autoReply; self.defaults=defaults
        let stored=defaults.object(forKey: Self.readKey(conversation.matchID)) as? Date
        lastReadAt=autoReply == nil ? (stored ?? .distantPast) : .distantPast
        isReady=secureSession == nil
    }

    /// A made-up conversation that already holds a first message.
    static func demo(matchID: UUID, name: String) -> ChatViewModel {
        ChatViewModel(
            conversation: ChatConversation(matchID: matchID, participantName: name,
                messages: [ChatMessage(sender: .match, text: "Hi", sentAt: Date().addingTimeInterval(-90))]),
            autoReply: "Hi")
    }

    private static func readKey(_ matchID: UUID) -> String { "chat.lastRead.\(matchID.uuidString.lowercased())" }

    /// Messages from the partner that arrived after the chat was last open.
    var unreadMessages: [ChatMessage] {
        conversation.messages.filter { $0.sender == .match && $0.sentAt > lastReadAt }
    }

    /// A sent message is read once the partner has read it or anything after it.
    func isReadByPartner(_ message: ChatMessage) -> Bool {
        if isDemo { return conversation.messages.contains { $0.sender == .match && $0.sentAt > message.sentAt } }
        guard let partnerReadAt else { return false }
        return message.sentAt <= partnerReadAt
    }

    /// Whether the server has the message; pending ones show a clock.
    func isDelivered(_ message: ChatMessage) -> Bool { !pendingIDs.contains(message.id) }
    @Published private var pendingIDs: Set<UUID> = []

    func markAllRead() {
        guard let newest=conversation.messages.last(where: { $0.sender == .match })?.sentAt, newest > lastReadAt else {
            if let secureSession { Task { try? await secureSession.markRead() } }
            return
        }
        lastReadAt=newest
        if !isDemo { defaults.set(newest, forKey: Self.readKey(conversation.matchID)) }
        if let secureSession { Task { try? await secureSession.markRead() } }
    }
    var canSend: Bool {
        isReady && !conversation.isBlocked && !conversation.isClosed && !draftMessage.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }
    private func updateSecurityState() {
        guard let secureSession else { return }
        isReady=secureSession.isReady; securityCode=secureSession.safetyCode
        requiresKeyConfirmation=secureSession.needsKeyConfirmation
        requiresDeviceReplacement=secureSession.needsDeviceReplacement
        securityCodeVerified=secureSession.codeIsVerified
        pendingMessageCount=secureSession.pendingCount
        conversation.isClosed=secureSession.isClosed
    }
    func refresh() async {
        guard let secureSession else { return }
        do {
            let messages=try await secureSession.refresh()
            // Keep unsent bubbles visible until the server acknowledges their IDs.
            let serverIDs=Set(messages.map(\.id))
            let pending=conversation.messages.filter { !serverIDs.contains($0.id) && $0.sender == .currentUser && !$0.isRead }
            conversation.messages=(messages+pending).sorted { $0.sentAt < $1.sentAt }
            pendingIDs=Set(pending.map(\.id))
            errorMessage=nil
        } catch SupabaseSetupError.wrongAccount {
            conversation.messages=[]; draftMessage=""; isReady=false; conversation.isClosed=true
            errorMessage=SupabaseSetupError.wrongAccount.localizedDescription
            return
        } catch { if !Task.isCancelled { errorMessage=error.localizedDescription } }
        let existing=Set(conversation.messages.map(\.id))
        let queued=secureSession.pendingMessages().filter { !existing.contains($0.id) }
        conversation.messages.append(contentsOf:queued)
        pendingIDs.formUnion(queued.map(\.id))
        updateSecurityState()
    }
    func clearError() { errorMessage=nil }
    /// The other person ended the match; nothing more can be sent.
    func conversationEnded() { conversation.isClosed=true; replyTask?.cancel(); isPartnerTyping=false }
    func sendMessage() {
        let trimmed=draftMessage.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canSend else { return }
        do {
            let message: ChatMessage
            if let secureSession { message=try secureSession.queue(trimmed) }
            else { message=ChatMessage(sender:.currentUser,text:trimmed,isRead:true) }
            conversation.messages.append(message); draftMessage=""; updateSecurityState()
            if isLive { pendingIDs.insert(message.id); Task { await refresh() } }
            if let autoReply { replyLater(autoReply) }
        } catch { errorMessage=error.localizedDescription }
    }
    func confirmSecurityCode() {
        do { try secureSession?.confirmSecurityCode(); errorMessage=nil; updateSecurityState(); Task { await refresh() } }
        catch { errorMessage=error.localizedDescription }
    }
    func replaceDevice() async {
        guard !isPerformingAction else { return }
        isPerformingAction=true; defer { isPerformingAction=false }
        do { try await secureSession?.prepare(replaceDevice:true); errorMessage=nil }
        catch { errorMessage=error.localizedDescription }
        updateSecurityState(); await refresh()
    }
    /// The demo answers after a short pause, typing first like a person would.
    private func replyLater(_ text: String) {
        replyTask?.cancel()
        replyTask=Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            isPartnerTyping=true
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            isPartnerTyping=false
            conversation.messages.append(ChatMessage(sender: .match, text: text))
        }
    }
    func blockMatch() { endMatch(block:true) }
    func endMatch(block: Bool = false) {
        guard !isPerformingAction else { return }
        if let secureSession {
            isPerformingAction=true
            Task {
                defer { isPerformingAction=false }
                do {
                    try await secureSession.end(block:block)
                    conversation.isBlocked=block; conversation.isClosed=true; errorMessage=nil; updateSecurityState()
                } catch { errorMessage=error.localizedDescription }
            }
        } else { conversation.isBlocked=block; conversation.isClosed=true }
    }
    func submitReport(reason: ReportReason, details: String) { submitReport(reason: reason, details: details, endMatch: false) }
    func submitReport(reason: ReportReason, details: String, endMatch: Bool) {
        guard !isPerformingAction else { return }
        if endMatch && !isLive { conversation.isClosed=true }
        let report=UserReport(matchID:conversation.matchID,reason:reason.rawValue,details:details.trimmingCharacters(in:.whitespacesAndNewlines))
        if let secureSession {
            isPerformingAction=true
            Task {
                defer { isPerformingAction=false }
                do {
                    try await secureSession.report(reason:reason.rawValue,details:report.details,endMatch:endMatch)
                    lastReport=report; showsReportSheet=false
                    if endMatch { conversation.isClosed=true; updateSecurityState() }
                }
                catch { errorMessage=error.localizedDescription }
            }
        } else { lastReport=report; showsReportSheet=false }
    }
}
