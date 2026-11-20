import Combine
import Foundation
import UIKit
import UserNotifications

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
    /// Reports against this account, refreshed daily and when a match ends.
    @Published private(set) var moderation: ModerationStatus?
    /// The active match's photo of the other person. Kept in memory only:
    /// the server stops sharing it once the match ends.
    @Published private(set) var partnerPhoto: UIImage?

    private let repository: SecureChatRepository?
    private let defaults: UserDefaults
    private let pushesArePermitted: () async -> Bool
    private let serverPushDelivered: (_ since: Date) async -> Bool
    private var sharedCards: Set<UUID> = []
    private var chatChanges: AnyCancellable?
    private var historyChats: [UUID: ChatViewModel] = [:]
    /// The Storage object `partnerPhoto` was downloaded from.
    private var partnerPhotoPath: String?
    private var lastPhotoAttempt = Date.distantPast
    /// The server's unread count the conversation was last decrypted at.
    /// The open chat refreshes itself; the home card only needs a new
    /// download when this changes.
    private var chatRefreshedAt: (matchID: UUID, unread: Int)?
    /// The live line to the active match while the app is open on it.
    private var following: (matchID: UUID, line: MatchFollowing)?
    /// The match whose live line failed to open: it is asked on a timer.
    private var followFailed: UUID?
    /// Resumes the waiting loop in `run`.
    private var waiter: CheckedContinuation<Void, Never>?
    /// Something asked for a refresh while nothing was waiting (during a
    /// refresh, or while the app was in the background).
    private var signalled = false

    // MARK: When the server is asked
    //
    // Pushes and the live line say when something changed, so an open app
    // asks only then:
    //   - a new match or an ended one arrives by push (`wake()`), at once;
    //   - with an active match the app listens on the match's private
    //     Realtime channel: messages, read receipts, keys, cards, the end;
    //   - opening the app asks when a server notification arrived meanwhile,
    //     and otherwise only after six hours, in case a push was lost.
    // Timers remain only where nothing else can tell: no pushes on this
    // phone (10 minutes), a live line that could not open (1 minute), and a
    // failed request (1 minute).

    /// Without pushes this phone can count on, an open app asks this often.
    static let pollWithoutPush: Duration = .seconds(10 * 60)
    /// With a match but no live line.
    static let pollWithoutLiveLine: Duration = .seconds(60)
    static let retryAfterFailure: Duration = .seconds(60)
    /// Coming back to the app asks the server only after this long, unless
    /// a push or a delivered notification says something changed.
    static let arrivalRecheckWithPush: TimeInterval = 6 * 60 * 60
    static let arrivalRecheckWithoutPush: TimeInterval = 10 * 60
    /// Pushes count as working when one arrived within this long.
    static let pushTrustWindow: TimeInterval = 30 * 24 * 60 * 60
    /// Reports end the match, which is checked then; otherwise once a day.
    static let moderationInterval: TimeInterval = 24 * 60 * 60

    init(repository: SecureChatRepository?, defaults: UserDefaults = .standard,
         pushesArePermitted: @escaping () async -> Bool = LiveMatchCenter.systemPushesArePermitted,
         serverPushDelivered: @escaping (_ since: Date) async -> Bool = LiveMatchCenter.systemServerPushDelivered) {
        self.repository = repository
        self.defaults = defaults
        self.pushesArePermitted = pushesArePermitted
        self.serverPushDelivered = serverPushDelivered
        // The match the app was closed on, so a cold start opens on it at
        // once instead of on the home screen until the server answers. The
        // first refresh confirms it, updates it or ends it.
        if repository != nil, let cached = Self.cachedMatch(defaults: defaults), cached.isActive {
            adopt(cached)
        }
        if repository != nil { pastMatches = Self.cachedHistory(defaults: defaults) ?? [] }
    }

    /// Runs while the app is in front and a match can exist. Mostly it waits.
    func run(ownProfile: @escaping () -> ProfileCreationState) async {
        guard repository != nil else { return }
        if Self.cachedHistory(defaults: defaults) == nil { await loadHistory() }
        if await asksOnArrival() { await refresh(ownProfile: ownProfile()) }
        while !Task.isCancelled {
            if Date().timeIntervalSince(lastModerationCheck) > Self.moderationInterval { await refreshModeration() }
            await followActiveMatch()
            await waitForSignal(upTo: await nextTimer())
            guard !Task.isCancelled else { break }
            await refresh(ownProfile: ownProfile())
        }
        await stopFollowing()
    }

    /// A push from the server: something changed, ask now.
    func wake() {
        lastServerPush = Date()
        signal()
    }

    /// This phone changed something that can change matches (it saved the
    /// profile): ask once.
    func serverMayHaveChanged() { signal() }

    private func asksOnArrival() async -> Bool {
        if signalled { return true }
        let elapsed = Date().timeIntervalSince(lastRefresh)
        if elapsed > (await pushIsTrusted() ? Self.arrivalRecheckWithPush : Self.arrivalRecheckWithoutPush) { return true }
        // A notification shown while the app was closed (it was not woken).
        return await serverPushDelivered(lastRefresh)
    }

    /// Nil: wait for a push or a signal on the live line, however long.
    private func nextTimer() async -> Duration? {
        if loadFailed { return Self.retryAfterFailure }
        if let match {
            return following?.matchID == match.id ? nil : Self.pollWithoutLiveLine
        }
        return await pushIsTrusted() ? nil : Self.pollWithoutPush
    }

    private func pushIsTrusted() async -> Bool {
        guard Date().timeIntervalSince(lastServerPush) < Self.pushTrustWindow else { return false }
        return await pushesArePermitted()
    }

    private func signal() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            signalled = true
        }
    }

    private func waitForSignal(upTo timeout: Duration?) async {
        if signalled { signalled = false; return }
        let timer = timeout.map { timeout in
            Task { [weak self] in
                guard (try? await Task.sleep(for: timeout)) != nil else { return }
                self?.signal()
            }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume() } else { waiter = continuation }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.signal() }
        }
        timer?.cancel()
        signalled = false
    }

    // MARK: Live line

    private func followActiveMatch() async {
        guard let repository, let match, match.isActive else { return await stopFollowing() }
        if following?.matchID == match.id || followFailed == match.id { return }
        await stopFollowing()
        let id = match.id, partner = match.partnerID
        do {
            if let line = try await repository.follow(id, onSignal: { [weak self] signal in
                self?.handle(signal, matchID: id, partnerID: partner)
            }) {
                following = (id, line)
                chat?.isFollowedLive = true
            } else {
                followFailed = id
            }
        } catch {
            followFailed = id
        }
    }

    private func stopFollowing() async {
        guard let following else { return }
        self.following = nil
        chat?.isFollowedLive = false
        await following.line.stop()
    }

    private func handle(_ signal: MatchSignal, matchID: UUID, partnerID: UUID) {
        guard match?.id == matchID else { return }
        // This phone's own actions need no news; a server action (by nil) does.
        if let by = signal.by, by != partnerID { return }
        switch signal.kind {
        case .message, .keys:
            // The conversation fetches only what is new; the badge counts
            // from it. No current_match needed.
            if let chat { Task { await chat.refresh() } } else { self.signal() }
        case .read:
            if let chat, chat.isOnScreen { Task { await chat.refresh() } }
        case .card, .ended:
            self.signal()
        case .connected:
            // Joining right after a refresh misses nothing.
            if Date().timeIntervalSince(lastRefresh) > 5 { self.signal() }
        }
    }

    // MARK: Remembered across launches

    private var lastRefresh: Date {
        get { defaults.object(forKey: Self.keyPrefix + "lastRefresh") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: Self.keyPrefix + "lastRefresh") }
    }
    private var lastServerPush: Date {
        get { defaults.object(forKey: Self.keyPrefix + "lastServerPush") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: Self.keyPrefix + "lastServerPush") }
    }
    private var lastModerationCheck: Date {
        get { defaults.object(forKey: Self.keyPrefix + "lastModerationCheck") as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: Self.keyPrefix + "lastModerationCheck") }
    }

    nonisolated static func systemPushesArePermitted() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// Whether a notification from the server (it carries a `kind`) was
    /// delivered after `since` and is still in Notification Center.
    nonisolated static func systemServerPushDelivered(since: Date) async -> Bool {
        await UNUserNotificationCenter.current().deliveredNotifications().contains {
            $0.date > since && $0.request.content.userInfo["kind"] != nil
        }
    }

    /// Every broken match, for My matches. Asked for when the list opens and
    /// whenever the active match ends; kept on the phone in between.
    func loadHistory() async {
        guard let repository, let all = try? await repository.matchHistory() else { return }
        for match in all { rememberPartnerCard(match) }
        pastMatches = all.filter { !$0.isActive }
        if let data = try? JSONEncoder().encode(pastMatches) { defaults.set(data, forKey: Self.historyKey) }
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
            // The partner's card is kept on this phone once seen, so the
            // server need not send it again on every poll.
            let knownCard = match.flatMap { defaults.string(forKey: Self.key("them", $0.id)) != nil ? $0.id : nil }
            var current = try await repository.currentMatch(knownCard: knownCard)
            loadFailed = false
            lastRefresh = Date()
            if let id = current?.id, current?.partnerCard == nil {
                current?.partnerCard = defaults.string(forKey: Self.key("them", id))
            }
            guard let current else {
                Self.clearCache(defaults: defaults)
                if match != nil {
                    // The other person broke it: it moves to My matches.
                    match = nil
                    chat = nil
                    chatChanges = nil
                    clearPartnerPhoto()
                    await stopFollowing()
                    await loadHistory()
                    // A report ends the match: the strike shows now.
                    await refreshModeration()
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
            // The first time registers this phone's key and decrypts anything
            // already sent; after that only a changed unread count needs it.
            // An open chat refreshes itself.
            if chat?.isOnScreen != true,
               chatRefreshedAt?.matchID != current.id || chatRefreshedAt?.unread != current.unreadCount {
                await chat?.refresh()
                // A failed download is tried again on the next poll.
                chatRefreshedAt = chat?.errorMessage == nil ? (current.id, current.unreadCount) : nil
            }
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
            chat?.isFollowedLive = following?.matchID == match.id
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
    /// server, which made the match; the cards supply the categories behind
    /// them, worked out once and then kept as they are.
    func snapshot(fallbackYou: ProfileCreationState) -> MatchSnapshot? {
        match.map { snapshot(of: $0, fallbackYou: fallbackYou) }
    }

    /// Any server match, active or broken. A broken one carries why it ended.
    func snapshot(of match: CloudChatMatch, fallbackYou: ProfileCreationState) -> MatchSnapshot {
        let you = frozenProfile(for: match.id) ?? fallbackYou.sharedCopy(today: .today())
        let card = partnerProfile(for: match)
        var them = card ?? ProfileCreationState(today: .today(), applicationLanguage: "en")
        if them.displayName.isEmpty { them.displayName = match.partnerName }
        let matchedAt = match.matchedAt ?? Date()
        let result: MatchResult
        if let frozen = frozenResult(for: match.id) {
            result = frozen
        } else {
            var computed = MatchResult(you: you, them: them,
                                       on: CalendarDate.today(calendar: BirthDateRules.calendar, now: matchedAt))
            computed.useServerScores(yours: match.ownScore, theirs: match.partnerScore)
            // Kept from the moment the partner's card is in: an app update
            // or a changed catalog never changes it afterwards.
            if card != nil { freeze(computed, for: match.id) }
            result = computed
        }
        var snapshot = MatchSnapshot(id: match.id, matchedAt: matchedAt, you: you, them: them, result: result)
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
            if let data = try? JSONEncoder().encode(pastMatches) { defaults.set(data, forKey: Self.historyKey) }
        }
        match = nil
        chat = nil
        chatChanges = nil
        clearPartnerPhoto()
        Task { await stopFollowing() }
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
        return ProfileCode.opened(data, expires: false)?.profile
    }

    private func frozenResult(for id: UUID) -> MatchResult? {
        defaults.data(forKey: Self.key("result", id)).flatMap { try? JSONDecoder().decode(MatchResult.self, from: $0) }
    }

    private func freeze(_ result: MatchResult, for id: UUID) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        defaults.set(data, forKey: Self.key("result", id))
    }

    private func shareCard(for id: UUID) async {
        guard let repository, !sharedCards.contains(id), let you = frozenProfile(for: id),
              let card = ProfileCode.card(for: you) else { return }
        do {
            try await repository.shareCard(id, card: card)
            sharedCards.insert(id)
        } catch {
            // Tried again on the next refresh.
        }
    }

    // MARK: - Cache

    nonisolated private static let cacheKey = "liveMatch.current.v1"
    nonisolated private static let historyKey = "liveMatch.history.v1"

    private static func cachedHistory(defaults: UserDefaults) -> [CloudChatMatch]? {
        defaults.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([CloudChatMatch].self, from: $0) }
    }

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

    /// Signing out: also what was learned about this account, so the next
    /// one starts by asking the server.
    nonisolated static func clearAccountCache(defaults: UserDefaults = .standard) {
        for key in [cacheKey, historyKey, keyPrefix + "lastRefresh", keyPrefix + "lastModerationCheck"] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Deleting the profile: the cached match and everything kept per match,
    /// including each partner's card (their age, area and answers) and the
    /// frozen copy of this profile. None of it may outlive the account.
    nonisolated static func clearLocalData(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    nonisolated private static let keyPrefix = "liveMatch."

    private static func key(_ kind: String, _ id: UUID) -> String {
        "\(keyPrefix)\(kind).\(id.uuidString.lowercased())"
    }
}
