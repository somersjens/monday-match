import SwiftUI

/// Polling is foreground-only; both participants can discover a server-created
/// match even when it was the other person's profile update that created it.
struct MatchingHubView: View {
    let repository: SecureChatRepository
    @Environment(\.scenePhase) private var scenePhase
    @State private var match: CloudChatMatch?
    @State private var selectedMatch: CloudChatMatch?
    @State private var loadFailed = false
    var body: some View {
        VStack(spacing: 8) {
            if let match {
                Button { selectedMatch=match } label: {
                    Label("\(match.partnerName) · \(Int((Double(match.ownScore+match.partnerScore)/2).rounded()))%",systemImage:"bubble.left.and.bubble.right.fill")
                }.buttonStyle(GlowButtonStyle())
                Text(L10n("You have a match. Open your private conversation."))
                    .font(.caption).foregroundStyle(OnboardingTheme.secondaryText)
            }
            if loadFailed {
                Text(L10n("Your match could not be refreshed. Trying again when connected."))
                    .font(.caption).foregroundStyle(OnboardingTheme.secondaryText)
            }
        }
        .task(id:scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { match=try await repository.currentMatch(); loadFailed=false }
                catch { if !Task.isCancelled { loadFailed=true } }
                do { try await Task.sleep(for:.seconds(5)) } catch { return }
            }
        }
        .sheet(item:$selectedMatch) { match in
            LiveChatScreen(match:match,repository:repository)
        }
    }
}
private struct LiveChatScreen: View {
    @StateObject private var model: ChatViewModel
    init(match: CloudChatMatch,repository: SecureChatRepository) {
        _model=StateObject(wrappedValue:ChatViewModel(
            conversation:ChatConversation(id:match.id,matchID:match.id,participantName:match.partnerName,messages:[]),
            secureSession:SecureChatSession(match:match,repository:repository)))
    }
    var body: some View { NavigationStack { ChatView(viewModel:model) }.preferredColorScheme(.dark) }
}
