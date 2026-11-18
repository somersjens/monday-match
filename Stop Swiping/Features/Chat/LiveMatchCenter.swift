import Combine
import Foundation
import UIKit

/// The account's one active server match and its conversation. Discovering a
/// match shares this phone's profile card and registers its chat key at once,
/// so the other person can write before this phone ever opens the chat.
@MainActor
final class LiveMatchCenter: ObservableObject {
    @Published private(set) var match: CloudChatMatch?
    @Published private(set) var chat: ChatViewModel?
    @Published private(set) var loadFailed = false
    /// Broken matches, newest first. Their conversations stay readable.
    @Published private(set) var pastMatches: [CloudChatMatch] = []
    /// Reports against this account, refreshed about once a minute.
    @Published private(set) var moderation: ModerationStatus?
    /// The active match's photo of the other person. Kept in memory only:
    /// the server stops sharing it once the match ends.
    @Published private(set) var partnerPhoto: UIImage?

    private let repository: SecureChatRepository?
    private let defaults: UserDefaults
    private var sharedCards: Set<UUID> = []
    private var chatChanges: AnyCancellable?
    private var historyChats: [UUID: ChatViewModel] = [:]
    private var lastModerationCheck = Date.distantPast
    /// The Storage object `partnerPhoto` was downloaded from.
    private var partnerPhotoPath: String?
    private var lastPhotoAttempt = Date.distantPast

    init(repository: SecureChatRepository?, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        // The match the app was closed on, so a cold start opens on it at
        // once instead of on the home screen until the server answers. The
        // first refresh confirms it, updates it or ends it.
        if repository != nil, let cached = Self.cachedMatch(defaults: defaults), cached.isActive {
            adopt(cached)
        }
    }

    /// Polls while the app is in front. The chat refreshes on its own clock
    /// once it is open, so this only keeps the home card and badge current.
    func run(ownProfile: @escaping () -> ProfileCreationState) async {
        guard repository != nil else { return }
        await loadHistory()
        while !Task.isCancelled {
            await refresh(ownProfile: ownProfile())
            if Date().timeIntervalSince(lastModerationCheck) > 60 { await refreshModeration() }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    /// Every broken match, for My matches. Asked for when the list opens and
    /// whenever the active match ends, not on every poll.
    func loadHistory() async {
        guard let repository, let all = try? await repository.matchHistory() else { return }
        for match in all { rememberPartnerCard(match) }
        pastMatches = all.filter { !$0.isActive }
    }

    func refreshModeration() async {
        guard let repository, let status = try? await repository.moderation() else { return }
        lastModerationCheck = Date()
        moderation = status
    }

    /// The notice for the newest strike has been read.
    func acknowledgeModeration() async {
        guard let repository else { return }
        try? await repository.acknowledgeModeration()
        await refreshModeration()
    }

    func refresh(ownProfile: ProfileCreationState) async {
        guard let repository else { return }
        do {
            let current = try await repository.currentMatch()
            loadFailed = false
            guard let current else {
                Self.clearCache(defaults: defaults)
                if match != nil {
                    // The other person broke it: it moves to My matches.
                    match = nil
                    chat = nil
                    chatChanges = nil
                    clearPartnerPhoto()
                    await loadHistory()
                }
                return
            }
            if current != match { cache(current) }
            adopt(current)
            rememberPartnerCard(current)
            chat?.partnerReadAt = current.partnerReadAt
            freezeOwnProfile(ownProfile, for: current.id)
            await shareCard(for: current.id)
            await loadPartnerPhoto(current)
            // Registers this phone's key and decrypts anything already sent.
            await chat?.refresh()
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    /// Makes `match` the active one, with a conversation of its own.
    private func adopt(_ match: CloudChatMatch) {
        if let repository, chat?.conversation.matchID != match.id {
            chat = ChatViewModel(
                conversation: ChatConversation(id: match.id, matchID: match.id,
                                               participantName: match.partnerName, messages: []),
                secureSession: SecureChatSession(match: match, repository: repository))
            // The home card shows the newest message and the unread badge.
            // Only what the card shows: forwarding every keystroke would redraw
            // the whole home screen, light and all, while typing.
            chatChanges = chat?.summaryChanges.sink { [weak self] in self?.objectWillChange.send() }
        }
        self.match = match
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
        match.map { snapshot(of: $0, fallbackYou: fallbackYou) }
    }

    /// Any server match, active or broken. A broken one carries why it ended.
    func snapshot(of match: CloudChatMatch, fallbackYou: ProfileCreationState) -> MatchSnapshot {
        let you = frozenProfile(for: match.id) ?? fallbackYou.sharedCopy(today: .today())
        var them = partnerProfile(for: match) ?? ProfileCreationState(today: .today(), applicationLanguage: "en")
        if them.displayName.isEmpty { them.displayName = match.partnerName }
        var snapshot = MatchSnapshot(id: match.id, matchedAt: match.matchedAt ?? Date(), you: you, them: them,
                                     fixedScores: .init(yours: match.ownScore, theirs: match.partnerScore))
        if let endedAt = match.endedAt {
            snapshot.ended = .init(at: endedAt, reason: match.endReason, byMe: match.endedByMe)
        }
        return snapshot
    }

    /// The name to list a match under; a deleted profile keeps the name
    /// from its card.
    func displayName(for match: CloudChatMatch) -> String {
        let name = partnerProfile(for: match)?.displayName ?? ""
        return name.isEmpty ? match.partnerName : name
    }

    /// The read-only conversation of a broken match: it decrypts with this
    /// phone's keys for that match and accepts no new messages.
    func historyChat(for match: CloudChatMatch) -> ChatViewModel? {
        guard let repository, !match.isActive else { return nil }
        if let existing = historyChats[match.id] { return existing }
        let chat = ChatViewModel(
            conversation: ChatConversation(id: match.id, matchID: match.id, participantName: displayName(for: match),
                                           messages: [], isClosed: true),
            secureSession: SecureChatSession(match: match, repository: repository))
        historyChats[match.id] = chat
        return chat
    }

    /// The first time a match is shown it plays the full arrival.
    func hasBeenSeen(_ id: UUID) -> Bool { defaults.bool(forKey: Self.key("seen", id)) }
    func markSeen(_ id: UUID) { defaults.set(true, forKey: Self.key("seen", id)) }

    /// Once the conversation has been opened, the app opens straight into it.
    func hasStartedChat(_ id: UUID) -> Bool { defaults.bool(forKey: Self.key("chatting", id)) }
    func markChatStarted(_ id: UUID) { defaults.set(true, forKey: Self.key("chatting", id)) }

    /// Called after breaking or reporting: the server match is gone and
    /// shows up under My matches.
    func forget() {
        Self.clearCache(defaults: defaults)
        if let match, let chat {
            var ended = match
            ended.endedAt = Date()
            ended.endedByMe = true
            ended.endReason = ended.endReason ?? .broken
            pastMatches.removeAll { $0.id == match.id }
            pastMatches.insert(ended, at: 0)
            historyChats[match.id] = chat
        }
        match = nil
        chat = nil
        chatChanges = nil
        clearPartnerPhoto()
    }

    // MARK: - Photo

    /// Downloads the partner's photo once per photo; a new photo replaces
    /// it on the next refresh. A failed download is tried again after a while.
    private func loadPartnerPhoto(_ match: CloudChatMatch) async {
        guard let repository else { return }
        guard let path = match.partnerPhotoPath else {
            clearPartnerPhoto()
            return
        }
        guard path != partnerPhotoPath, Date().timeIntervalSince(lastPhotoAttempt) > 30 else { return }
        lastPhotoAttempt = Date()
        guard let data = try? await repository.partnerPhoto(path: path),
              let image = await Self.decodedPhoto(data),
              self.match?.id == match.id else { return }
        partnerPhoto = image
        partnerPhotoPath = path
    }

    private func clearPartnerPhoto() {
        partnerPhoto = nil
        partnerPhotoPath = nil
        lastPhotoAttempt = .distantPast
    }

    /// Decoded off the main actor, so the first draw doesn't stall.
    private nonisolated static func decodedPhoto(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }.value
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

    /// The partner's card is kept on this phone once seen, so the profile
    /// can still be opened after they delete their account.
    private func rememberPartnerCard(_ match: CloudChatMatch) {
        guard let card = match.partnerCard else { return }
        defaults.set(card, forKey: Self.key("them", match.id))
    }

    private func partnerProfile(for match: CloudChatMatch) -> ProfileCreationState? {
        if let profile = match.partnerProfile { return profile }
        guard let card = defaults.string(forKey: Self.key("them", match.id)),
              let data = Data(base64Encoded: card) else { return nil }
        return ProfileCode.decoded(data)
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

    // MARK: - Cache

    nonisolated private static let cacheKey = "liveMatch.current.v1"

    private func cache(_ match: CloudChatMatch) {
        guard let data = try? JSONEncoder().encode(match) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    private static func cachedMatch(defaults: UserDefaults) -> CloudChatMatch? {
        defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(CloudChatMatch.self, from: $0) }
    }

    /// Signing out or deleting the profile: the next account must not
    /// open on this one's match.
    nonisolated static func clearCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: cacheKey)
    }

    private static func key(_ kind: String, _ id: UUID) -> String {
        "liveMatch.\(kind).\(id.uuidString.lowercased())"
    }
}
