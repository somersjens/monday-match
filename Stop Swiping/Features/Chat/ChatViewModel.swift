import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var conversation: ChatConversation {
        didSet { if conversation != oldValue { onConversationChange?(conversation) } }
    }
    /// Keeps a demo conversation on the phone, so the app reopens in it.
    var onConversationChange: ((ChatConversation) -> Void)?
    /// What is being typed. Kept apart so a keystroke only redraws the
    /// composer, not every view that watches the conversation.
    let draft = ChatDraft()
    var draftMessage: String {
        get { draft.text }
        set { draft.text = newValue }
    }
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
    /// The meet-in-a-public-place notice at the top, until it is closed.
    @Published private(set) var showsSafetyNotice: Bool
    let secureSession: SecureChatSession?
    /// Set by a chat view while it polls, so the home screen polls less.
    var isOnScreen = false
    /// The last time this person opened the chat or sent something.
    private var lastActivity = Date.distantPast
    /// The match's live line is open (`LiveMatchCenter`): it refreshes this
    /// conversation whenever the server signals a change.
    var isFollowedLive = false
    /// How long an open chat waits before asking the server again. With a
    /// live line only a rare safety check; without one quick while messages
    /// go back and forth, slower once it has been quiet for a minute.
    var pollInterval: Duration {
        if isFollowedLive { return .seconds(5 * 60) }
        let newest = max(lastActivity, conversation.messages.last?.sentAt ?? .distantPast)
        return Date().timeIntervalSince(newest) < 60 ? .seconds(3) : .seconds(10)
    }
    /// The chat was opened or brought back to the front.
    func noteActivity() { lastActivity = Date() }
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
        showsSafetyNotice = !defaults.bool(forKey: Self.safetyNoticeKey(conversation.matchID))
        isReady=secureSession == nil
    }

    /// A made-up conversation that already holds a first message.
    static func demo(matchID: UUID, name: String) -> ChatViewModel {
        ChatViewModel(
            conversation: ChatConversation(matchID: matchID, participantName: name,
                messages: [ChatMessage(sender: .match, text: "Hi", sentAt: Date().addingTimeInterval(-90))]),
            autoReply: "Hi")
    }

    /// A demo conversation from an earlier launch, carrying on where it was.
    static func demo(resuming conversation: ChatConversation) -> ChatViewModel {
        ChatViewModel(conversation: conversation, autoReply: "Hi")
    }

    private nonisolated static let readKeyPrefix = "chat.lastRead."
    private static func readKey(_ matchID: UUID) -> String { readKeyPrefix + matchID.uuidString.lowercased() }
    private nonisolated static let safetyNoticeKeyPrefix = "chat.safetyNoticeClosed."
    private static func safetyNoticeKey(_ matchID: UUID) -> String { safetyNoticeKeyPrefix + matchID.uuidString.lowercased() }

    /// Closed once per match; a new match shows it again.
    func dismissSafetyNotice() {
        showsSafetyNotice = false
        defaults.set(true, forKey: Self.safetyNoticeKey(conversation.matchID))
    }

    /// Deleting the profile: how far each conversation was read goes too,
    /// and which safety notices were closed.
    nonisolated static func clearReadPositions(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(readKeyPrefix) || key.hasPrefix(safetyNoticeKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

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

    /// Fires when what the home screen shows changes: messages, read state
    /// and unsent ones. Typing, typing dots and errors stay out of it.
    var summaryChanges: AnyPublisher<Void, Never> {
        Publishers.Merge3(
            $conversation.removeDuplicates().dropFirst().map { _ in () },
            $lastReadAt.removeDuplicates().dropFirst().map { _ in () },
            $pendingIDs.removeDuplicates().dropFirst().map { _ in () })
            .eraseToAnyPublisher()
    }

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
            if let read=secureSession.partnerReadAt, read > (partnerReadAt ?? .distantPast) { partnerReadAt=read }
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
            noteActivity()
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
                    try await secureSession.breakMatch()
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
                    try await secureSession.report(reason:reason.rawValue,details:report.details,breakMatch:endMatch)
                    lastReport=report; showsReportSheet=false
                    if endMatch { conversation.isClosed=true; updateSecurityState() }
                }
                catch { errorMessage=error.localizedDescription }
            }
        } else { lastReport=report; showsReportSheet=false }
    }
}

/// The composer's text, observed only by the composer.
@MainActor
final class ChatDraft: ObservableObject {
    @Published var text = ""
}
