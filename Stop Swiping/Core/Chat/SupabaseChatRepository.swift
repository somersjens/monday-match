import Foundation
import Supabase

struct CloudChatMatch: Codable, Identifiable, Equatable {
    let id: UUID
    let partnerID: UUID
    let partnerName: String
    let ownScore: Int
    let partnerScore: Int
    var matchedAt: Date? = nil
    /// The partner's compact profile code, once their phone has shared it.
    var partnerCard: String? = nil
    /// Messages from the partner after the last one this account read.
    var unreadCount: Int = 0
    var lastMessageAt: Date? = nil
    /// When the newest message the partner has read was sent.
    var partnerReadAt: Date? = nil
    /// Set once the match is broken. The conversation stays readable but
    /// accepts no more messages, and the two can never be matched again.
    var endedAt: Date? = nil
    var endReason: EndReason? = nil
    /// This account broke the match (or reported and broke it).
    var endedByMe = false
    /// The partner's matching photo in Storage, only while the match is active.
    var partnerPhotoPath: String? = nil
    /// The server attested that photo with a live scan.
    var partnerPhotoVerified = false

    /// Why a match ended, as the server records it.
    enum EndReason: String, Codable {
        /// One of the two broke the match.
        case broken
        /// One of the two reported the other and broke the match.
        case reported
        /// One of the two deleted their profile or account.
        case profileDeleted = "profile_deleted"
        /// One of the two was blocked or banned after reports.
        case moderation
    }

    enum CodingKeys: String, CodingKey {
        case id, partnerID = "partner_id", partnerName = "partner_name", ownScore = "own_score", partnerScore = "partner_score"
        case matchedAt = "matched_at", partnerCard = "partner_card", unreadCount = "unread_count"
        case lastMessageAt = "last_message_at", partnerReadAt = "partner_read_at"
        case endedAt = "ended_at", endReason = "end_reason", endedByMe = "ended_by_me"
        case partnerPhotoPath = "partner_photo", partnerPhotoVerified = "partner_photo_verified"
    }
    init(id: UUID, partnerID: UUID, partnerName: String, ownScore: Int, partnerScore: Int,
         matchedAt: Date? = nil, partnerCard: String? = nil, unreadCount: Int = 0,
         lastMessageAt: Date? = nil, partnerReadAt: Date? = nil,
         endedAt: Date? = nil, endReason: EndReason? = nil, endedByMe: Bool = false,
         partnerPhotoPath: String? = nil, partnerPhotoVerified: Bool = false) {
        self.id = id; self.partnerID = partnerID; self.partnerName = partnerName
        self.ownScore = ownScore; self.partnerScore = partnerScore; self.matchedAt = matchedAt
        self.partnerCard = partnerCard; self.unreadCount = unreadCount
        self.lastMessageAt = lastMessageAt; self.partnerReadAt = partnerReadAt
        self.endedAt = endedAt; self.endReason = endReason; self.endedByMe = endedByMe
        self.partnerPhotoPath = partnerPhotoPath; self.partnerPhotoVerified = partnerPhotoVerified
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        partnerID = try c.decode(UUID.self, forKey: .partnerID)
        // The server stores whatever the other phone uploaded; never let a
        // name written past the app's own limit break the layout here.
        partnerName = ProfileNameRules.normalized(try c.decodeIfPresent(String.self, forKey: .partnerName) ?? "")
        ownScore = try c.decode(Int.self, forKey: .ownScore)
        partnerScore = try c.decode(Int.self, forKey: .partnerScore)
        matchedAt = try? c.decodeIfPresent(Date.self, forKey: .matchedAt)
        partnerCard = try c.decodeIfPresent(String.self, forKey: .partnerCard)
        unreadCount = (try? c.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? 0
        lastMessageAt = try? c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        partnerReadAt = try? c.decodeIfPresent(Date.self, forKey: .partnerReadAt)
        endedAt = try? c.decodeIfPresent(Date.self, forKey: .endedAt)
        endReason = try? c.decodeIfPresent(EndReason.self, forKey: .endReason)
        endedByMe = (try? c.decodeIfPresent(Bool.self, forKey: .endedByMe)) ?? false
        partnerPhotoPath = try? c.decodeIfPresent(String.self, forKey: .partnerPhotoPath)
        partnerPhotoVerified = (try? c.decodeIfPresent(Bool.self, forKey: .partnerPhotoVerified)) ?? false
    }
    /// Only for the copy kept on this phone between launches.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(partnerID, forKey: .partnerID)
        try c.encode(partnerName, forKey: .partnerName)
        try c.encode(ownScore, forKey: .ownScore)
        try c.encode(partnerScore, forKey: .partnerScore)
        try c.encodeIfPresent(matchedAt, forKey: .matchedAt)
        try c.encodeIfPresent(partnerCard, forKey: .partnerCard)
        try c.encode(unreadCount, forKey: .unreadCount)
        try c.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
        try c.encodeIfPresent(partnerReadAt, forKey: .partnerReadAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encodeIfPresent(endReason, forKey: .endReason)
        try c.encode(endedByMe, forKey: .endedByMe)
        try c.encodeIfPresent(partnerPhotoPath, forKey: .partnerPhotoPath)
        try c.encode(partnerPhotoVerified, forKey: .partnerPhotoVerified)
    }

    var isActive: Bool { endedAt == nil }

    /// The partner's profile as they shared it for this match.
    var partnerProfile: ProfileCreationState? {
        guard let partnerCard else { return nil }
        return ProfileCode.profile(fromCard: partnerCard)
    }

    var average: Int { Int((Double(ownScore + partnerScore) / 2).rounded()) }
}
struct CloudChatBundle: Decodable {
    struct PublicBundle: Codable {
        let `protocol`: String
        let key: Data
    }
    let userID: UUID
    let deviceID: UUID
    let bundle: PublicBundle
    let revokedAt: Date?
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", deviceID = "device_id", bundle = "public_bundle", revokedAt = "revoked_at"
    }
}
nonisolated struct CloudChatMessage: Decodable {
    let id: Int64
    let senderID: UUID
    let messageID: UUID
    let senderDeviceID: UUID
    let recipientDeviceID: UUID
    let ciphertext: String
    let protocolVersion: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey {
        case id, senderID = "sender_id", messageID = "client_message_id", senderDeviceID = "sender_device_id"
        case recipientDeviceID = "recipient_device_id", ciphertext, protocolVersion = "protocol_version", createdAt = "created_at"
    }
}

/// One look at an open chat: whether it ended, a fingerprint of the key
/// bundles (fetched in full only when it changes), the partner's read
/// receipt and the messages after the cursor.
nonisolated struct ChatPoll: Decodable {
    let closed: Bool
    /// Nil when unknown: the bundles are then fetched every time.
    let keys: String?
    let partnerReadAt: Date?
    let messages: [CloudChatMessage]
    enum CodingKeys: String, CodingKey {
        case closed, keys, partnerReadAt = "partner_read_at", messages
    }
    init(closed: Bool, keys: String?, partnerReadAt: Date?, messages: [CloudChatMessage]) {
        self.closed = closed; self.keys = keys; self.partnerReadAt = partnerReadAt; self.messages = messages
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        closed = try c.decode(Bool.self, forKey: .closed)
        keys = try c.decodeIfPresent(String.self, forKey: .keys)
        partnerReadAt = try? c.decodeIfPresent(Date.self, forKey: .partnerReadAt)
        messages = try c.decodeIfPresent([CloudChatMessage].self, forKey: .messages) ?? []
    }
}

/// Something changed in a match, as the database announces it on the
/// match's private Realtime channel. Never content: the app fetches that.
struct MatchSignal: Equatable, Sendable {
    enum Kind: String, Sendable {
        case message, read, keys, card, ended
        /// The channel (re)joined: anything may have changed while it was down.
        case connected
    }
    let kind: Kind
    /// Who did it; nil for the server itself (a moderation end).
    let by: UUID?
}

/// A live line to one match, held while the app is open on it.
@MainActor
protocol MatchFollowing: AnyObject {
    func stop() async
}

/// Reports against this account: 1 is a warning, 2 blocks matching and chat
/// for 7 days, 3 bans the account.
nonisolated struct ModerationStatus: Decodable, Equatable {
    let strikes: Int
    let strikesSeen: Int
    let suspendedUntil: Date?
    let banned: Bool
    enum CodingKeys: String, CodingKey {
        case strikes, strikesSeen = "strikes_seen", suspendedUntil = "suspended_until", banned
    }
    init(strikes: Int, strikesSeen: Int, suspendedUntil: Date?, banned: Bool) {
        self.strikes = strikes; self.strikesSeen = strikesSeen; self.suspendedUntil = suspendedUntil; self.banned = banned
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strikes = try c.decodeIfPresent(Int.self, forKey: .strikes) ?? 0
        strikesSeen = try c.decodeIfPresent(Int.self, forKey: .strikesSeen) ?? 0
        suspendedUntil = try? c.decodeIfPresent(Date.self, forKey: .suspendedUntil)
        banned = try c.decodeIfPresent(Bool.self, forKey: .banned) ?? false
    }

    func isSuspended(now: Date = Date()) -> Bool { !banned && (suspendedUntil.map { $0 > now } ?? false) }
    /// A new strike this person has not acknowledged yet.
    var hasUnseenNotice: Bool { strikes > strikesSeen }
}

@MainActor
protocol SecureChatRepository {
    var scope: String { get }
    func userID() async throws -> UUID
    func currentMatch() async throws -> CloudChatMatch?
    /// The same, leaving out the partner's card when `knownCard` is the
    /// match whose card this phone already keeps.
    func currentMatch(knownCard: UUID?) async throws -> CloudChatMatch?
    /// What an open chat needs on each refresh, in one request.
    func poll(_ matchID: UUID, after: Int64?) async throws -> ChatPoll
    /// Listens for changes to a match until stopped. Nil when this
    /// repository cannot listen; the caller then asks on a timer.
    func follow(_ matchID: UUID, onSignal: @escaping @MainActor (MatchSignal) -> Void) async throws -> MatchFollowing?
    func isClosed(_ matchID: UUID) async throws -> Bool
    func bundles(_ matchID: UUID) async throws -> [CloudChatBundle]
    func register(_ matchID: UUID, deviceID: UUID, key: Data, replace: Bool) async throws
    func messages(_ matchID: UUID, after: Int64?) async throws -> [CloudChatMessage]
    func send(_ matchID: UUID, pending: ChatPendingMessage) async throws
    /// Ends the match for both people. History stays readable.
    func breakMatch(_ matchID: UUID) async throws
    func report(_ matchID: UUID, reason: String, details: String) async throws
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool) async throws
    func shareCard(_ matchID: UUID, card: String) async throws
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws
    /// Every match this account has had, newest first, active and broken.
    func matchHistory() async throws -> [CloudChatMatch]
    func moderation() async throws -> ModerationStatus
    func acknowledgeModeration() async throws
    /// The partner's matching photo; Storage only allows it during an active match.
    func partnerPhoto(path: String) async throws -> Data
}

extension SecureChatRepository {
    func follow(_ matchID: UUID, onSignal: @escaping @MainActor (MatchSignal) -> Void) async throws -> MatchFollowing? { nil }
    func currentMatch(knownCard: UUID?) async throws -> CloudChatMatch? { try await currentMatch() }
    func poll(_ matchID: UUID, after: Int64?) async throws -> ChatPoll {
        let closed = try await isClosed(matchID)
        return ChatPoll(closed: closed, keys: nil, partnerReadAt: nil, messages: try await messages(matchID, after: after))
    }
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool) async throws {
        try await report(matchID, reason: reason, details: details)
        if breakMatch { try await self.breakMatch(matchID) }
    }
    func shareCard(_ matchID: UUID, card: String) async throws {}
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws {}
    func matchHistory() async throws -> [CloudChatMatch] { [] }
    func moderation() async throws -> ModerationStatus { .init(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: false) }
    func acknowledgeModeration() async throws {}
    func partnerPhoto(path: String) async throws -> Data { throw CancellationError() }
}

@MainActor
final class SupabaseChatRepository: SecureChatRepository {
    let client: SupabaseClient
    let scope: String
    init(client: SupabaseClient, projectURL: URL) { self.client = client; scope = projectURL.absoluteString }
    func userID() async throws -> UUID {
        let uid = try await client.auth.session.user.id
        return uid
    }
    func currentMatch() async throws -> CloudChatMatch? {
        try await client.rpc("current_match").execute().value
    }
    func currentMatch(knownCard: UUID?) async throws -> CloudChatMatch? {
        guard let knownCard else { return try await currentMatch() }
        do {
            return try await client.rpc("current_match", params: ["p_known_card": knownCard.uuidString]).execute().value
        } catch let error as PostgrestError where Self.isMissingFunction(error) {
            // A server without 202611190002 yet.
            return try await currentMatch()
        }
    }
    func poll(_ matchID: UUID, after: Int64?) async throws -> ChatPoll {
        struct Params: Encodable { let p_match_id: UUID; let p_after: Int64? }
        do {
            return try await client.rpc("chat_poll", params: Params(p_match_id: matchID, p_after: after)).execute().value
        } catch let error as PostgrestError where Self.isMissingFunction(error) {
            let closed = try await isClosed(matchID)
            return ChatPoll(closed: closed, keys: nil, partnerReadAt: nil, messages: try await messages(matchID, after: after))
        }
    }
    func follow(_ matchID: UUID, onSignal: @escaping @MainActor (MatchSignal) -> Void) async throws -> MatchFollowing? {
        let channel = client.channel("match:\(matchID.uuidString.lowercased())") { $0.isPrivate = true }
        let changes = channel.onBroadcast(event: "changed") { message in
            // The broadcast's own payload sits under "payload".
            let body = message["payload"]?.objectValue ?? message
            guard let kind = body["what"]?.stringValue.flatMap(MatchSignal.Kind.init(rawValue:)) else { return }
            let signal = MatchSignal(kind: kind, by: body["by"]?.stringValue.flatMap(UUID.init(uuidString:)))
            Task { @MainActor in onSignal(signal) }
        }
        let status = channel.onStatusChange { status in
            guard status == .subscribed else { return }
            Task { @MainActor in onSignal(MatchSignal(kind: .connected, by: nil)) }
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            changes.cancel(); status.cancel()
            await client.removeChannel(channel)
            throw error
        }
        return SupabaseMatchFollow(client: client, channel: channel, subscriptions: [changes, status])
    }
    /// PostgREST's answer for a function the database does not have.
    private static func isMissingFunction(_ error: PostgrestError) -> Bool { error.code == "PGRST202" }
    func isClosed(_ matchID: UUID) async throws -> Bool {
        struct Row: Decodable { let ended_at: Date? }
        let rows: [Row] = try await client.from("matches").select("ended_at").eq("id",value:matchID)
            .limit(1).execute().value
        return rows.isEmpty || rows[0].ended_at != nil
    }
    func bundles(_ matchID: UUID) async throws -> [CloudChatBundle] {
        try await client.from("match_key_bundles").select().eq("match_id",value:matchID).execute().value
    }
    func register(_ matchID: UUID, deviceID: UUID, key: Data, replace: Bool) async throws {
        struct Params: Encodable {
            let p_match_id: UUID; let p_device_id: UUID
            let p_public_bundle: CloudChatBundle.PublicBundle; let p_replace_device: Bool
        }
        try await client.rpc("register_chat_device",params:Params(p_match_id:matchID,p_device_id:deviceID,
            p_public_bundle:.init(protocol:ChatCryptography.protocolVersion,key:key),p_replace_device:replace)).execute()
    }
    func messages(_ matchID: UUID, after: Int64?) async throws -> [CloudChatMessage] {
        var request = client.from("encrypted_messages").select().eq("match_id",value:matchID)
        if let after { request = request.gt("id",value:String(after)) }
        return try await request.order("id",ascending:after != nil).limit(100).execute().value
    }
    func send(_ matchID: UUID, pending: ChatPendingMessage) async throws {
        do {
            let _: Int64 = try await client.rpc("send_encrypted_message",params:[
                "p_match_id":matchID.uuidString,"p_client_message_id":pending.id.uuidString,
                "p_sender_device_id":pending.senderDeviceID.uuidString,"p_recipient_device_id":pending.recipientDeviceID.uuidString,
                "p_ciphertext":pending.ciphertext,"p_protocol_version":ChatCryptography.protocolVersion]).execute().value
        } catch let error as PostgrestError where error.message.contains("Message limit reached") {
            // 60 a minute and 5 MB a day per sender (202611190001_abuse_limits.sql).
            // The message stays queued and goes out on a later refresh.
            throw SecureChatError.sendingTooFast
        }
    }
    func breakMatch(_ matchID: UUID) async throws {
        try await client.rpc("break_match",params:["p_match_id":matchID.uuidString]).execute()
    }
    func report(_ matchID: UUID, reason: String, details: String) async throws {
        try await report(matchID, reason: reason, details: details, breakMatch: false)
    }
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool) async throws {
        struct Params: Encodable { let p_match_id: UUID; let p_reason: String; let p_details: String; let p_break_match: Bool }
        try await client.rpc("report_partner",params:Params(p_match_id:matchID,p_reason:reason,p_details:details,p_break_match:breakMatch)).execute()
    }
    func matchHistory() async throws -> [CloudChatMatch] {
        try await client.rpc("my_matches").execute().value
    }
    func moderation() async throws -> ModerationStatus {
        nonisolated struct Status: Decodable { let moderation: ModerationStatus }
        let status: Status = try await client.rpc("matching_status").execute().value
        return status.moderation
    }
    func acknowledgeModeration() async throws {
        try await client.rpc("acknowledge_moderation").execute()
    }
    func shareCard(_ matchID: UUID, card: String) async throws {
        try await client.rpc("share_match_card",params:["p_match_id":matchID.uuidString,"p_card":card]).execute()
    }
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws {
        struct Params: Encodable { let p_match_id: UUID; let p_message_id: Int64 }
        try await client.rpc("mark_chat_read",params:Params(p_match_id:matchID,p_message_id:messageID)).execute()
    }
    func partnerPhoto(path: String) async throws -> Data {
        try await client.storage.from(SupabaseProfilePhotoUploader.bucket).download(path: path)
    }
}

@MainActor
private final class SupabaseMatchFollow: MatchFollowing {
    private let client: SupabaseClient
    private let channel: RealtimeChannelV2
    private var subscriptions: [RealtimeSubscription]
    init(client: SupabaseClient, channel: RealtimeChannelV2, subscriptions: [RealtimeSubscription]) {
        self.client = client; self.channel = channel; self.subscriptions = subscriptions
    }
    func stop() async {
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        await client.removeChannel(channel)
    }
}
