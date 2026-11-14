import Combine
import Foundation

/// The account's one active server match and its conversation. Discovering a
/// match shares this phone's profile card and registers its chat key at once,
/// so the other person can write before this phone ever opens the chat.
@MainActor
final class LiveMatchCenter: ObservableObject {
    @Published private(set) var match: CloudChatMatch?
    @Published private(set) var chat: ChatViewModel?
    @Published private(set) var loadFailed = false

    private let repository: SecureChatRepository?
    private let defaults: UserDefaults
    private var sharedCards: Set<UUID> = []
    private var chatChanges: AnyCancellable?

    init(repository: SecureChatRepository?, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
    }

    /// Polls while the app is in front. The chat refreshes on its own clock
    /// once it is open, so this only keeps the home card and badge current.
    func run(ownProfile: @escaping () -> ProfileCreationState) async {
        guard repository != nil else { return }
        while !Task.isCancelled {
            await refresh(ownProfile: ownProfile())
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    func refresh(ownProfile: ProfileCreationState) async {
        guard let repository else { return }
        do {
            let current = try await repository.currentMatch()
            loadFailed = false
            guard let current else {
                match = nil
                chat = nil
                chatChanges = nil
                return
            }
            if chat?.conversation.matchID != current.id {
                chat = ChatViewModel(
                    conversation: ChatConversation(id: current.id, matchID: current.id,
                                                   participantName: current.partnerName, messages: []),
                    secureSession: SecureChatSession(match: current, repository: repository))
                // The home card shows the newest message and the unread badge.
                chatChanges = chat?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            }
            match = current
            chat?.partnerReadAt = current.partnerReadAt
            freezeOwnProfile(ownProfile, for: current.id)
            await shareCard(for: current.id)
            // Registers this phone's key and decrypts anything already sent.
            await chat?.refresh()
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    /// Messages waiting to be read, from the decrypted chat when it has
    /// loaded and from the server's count before that.
    var unreadMessages: [ChatMessage] { chat?.unreadMessages ?? [] }
    var unreadCount: Int {
        guard let chat else { return match?.unreadCount ?? 0 }
        return chat.conversation.messages.isEmpty ? (match?.unreadCount ?? 0) : chat.unreadMessages.count
    }

    /// The match as both profiles were when it was made. Scores come from the
    /// server, which made the match; the cards supply the answers behind them.
    func snapshot(fallbackYou: ProfileCreationState) -> MatchSnapshot? {
        guard let match else { return nil }
        let you = frozenProfile(for: match.id) ?? fallbackYou.sharedCopy(today: .today())
        var them = match.partnerProfile ?? ProfileCreationState(today: .today(), applicationLanguage: "en")
        if them.displayName.isEmpty { them.displayName = match.partnerName }
        return MatchSnapshot(id: match.id, matchedAt: match.matchedAt ?? Date(), you: you, them: them,
                             fixedScores: .init(yours: match.ownScore, theirs: match.partnerScore))
    }

    /// The first time a match is shown it plays the full arrival.
    func hasBeenSeen(_ id: UUID) -> Bool { defaults.bool(forKey: Self.key("seen", id)) }
    func markSeen(_ id: UUID) { defaults.set(true, forKey: Self.key("seen", id)) }

    /// Called after breaking or reporting: the server match is gone.
    func forget() {
        match = nil
        chat = nil
        chatChanges = nil
    }

    // MARK: - Cards

    private func freezeOwnProfile(_ profile: ProfileCreationState, for id: UUID) {
        guard frozenProfile(for: id) == nil,
              let data = try? JSONEncoder().encode(profile.sharedCopy(today: .today())) else { return }
        defaults.set(data, forKey: Self.key("you", id))
    }

    private func frozenProfile(for id: UUID) -> ProfileCreationState? {
        defaults.data(forKey: Self.key("you", id)).flatMap { try? JSONDecoder().decode(ProfileCreationState.self, from: $0) }
    }

    private func shareCard(for id: UUID) async {
        guard let repository, !sharedCards.contains(id), let you = frozenProfile(for: id),
              let card = ProfileCode.encoded(you)?.base64EncodedString() else { return }
        do {
            try await repository.shareCard(id, card: card)
            sharedCards.insert(id)
        } catch {
            // Tried again on the next refresh.
        }
    }

    private static func key(_ kind: String, _ id: UUID) -> String {
        "liveMatch.\(kind).\(id.uuidString.lowercased())"
    }
}
