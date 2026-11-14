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
    let secureSession: SecureChatSession?
    var isLive: Bool { secureSession != nil }
    init(conversation: ChatConversation, secureSession: SecureChatSession? = nil) {
        self.conversation=conversation; self.secureSession=secureSession
        isReady=secureSession == nil
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
            errorMessage=nil
        } catch SupabaseSetupError.wrongAccount {
            conversation.messages=[]; draftMessage=""; isReady=false; conversation.isClosed=true
            errorMessage=SupabaseSetupError.wrongAccount.localizedDescription
            return
        } catch { if !Task.isCancelled { errorMessage=error.localizedDescription } }
        let existing=Set(conversation.messages.map(\.id))
        conversation.messages.append(contentsOf:secureSession.pendingMessages().filter { !existing.contains($0.id) })
        updateSecurityState()
    }
    func clearError() { errorMessage=nil }
    func sendMessage() {
        let trimmed=draftMessage.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canSend else { return }
        do {
            let message: ChatMessage
            if let secureSession { message=try secureSession.queue(trimmed) }
            else { message=ChatMessage(sender:.currentUser,text:trimmed,isRead:true) }
            conversation.messages.append(message); draftMessage=""; updateSecurityState()
            if isLive { Task { await refresh() } }
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
    func submitReport(reason: ReportReason, details: String) {
        guard !isPerformingAction else { return }
        let report=UserReport(matchID:conversation.matchID,reason:reason.rawValue,details:details.trimmingCharacters(in:.whitespacesAndNewlines))
        if let secureSession {
            isPerformingAction=true
            Task {
                defer { isPerformingAction=false }
                do { try await secureSession.report(reason:reason.rawValue,details:report.details); lastReport=report; showsReportSheet=false }
                catch { errorMessage=error.localizedDescription }
            }
        } else { lastReport=report; showsReportSheet=false }
    }
}
