import Foundation
import Supabase

struct CloudChatMatch: Decodable, Identifiable, Equatable {
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
    enum CodingKeys: String, CodingKey {
        case id, partnerID = "partner_id", partnerName = "partner_name", ownScore = "own_score", partnerScore = "partner_score"
        case matchedAt = "matched_at", partnerCard = "partner_card", unreadCount = "unread_count"
        case lastMessageAt = "last_message_at", partnerReadAt = "partner_read_at"
    }
    init(id: UUID, partnerID: UUID, partnerName: String, ownScore: Int, partnerScore: Int,
         matchedAt: Date? = nil, partnerCard: String? = nil, unreadCount: Int = 0,
         lastMessageAt: Date? = nil, partnerReadAt: Date? = nil) {
        self.id = id; self.partnerID = partnerID; self.partnerName = partnerName
        self.ownScore = ownScore; self.partnerScore = partnerScore; self.matchedAt = matchedAt
        self.partnerCard = partnerCard; self.unreadCount = unreadCount
        self.lastMessageAt = lastMessageAt; self.partnerReadAt = partnerReadAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        partnerID = try c.decode(UUID.self, forKey: .partnerID)
        partnerName = try c.decodeIfPresent(String.self, forKey: .partnerName) ?? ""
        ownScore = try c.decode(Int.self, forKey: .ownScore)
        partnerScore = try c.decode(Int.self, forKey: .partnerScore)
        matchedAt = try? c.decodeIfPresent(Date.self, forKey: .matchedAt)
        partnerCard = try c.decodeIfPresent(String.self, forKey: .partnerCard)
        unreadCount = (try? c.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? 0
        lastMessageAt = try? c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        partnerReadAt = try? c.decodeIfPresent(Date.self, forKey: .partnerReadAt)
    }

    /// The partner's profile as they shared it for this match.
    var partnerProfile: ProfileCreationState? {
        guard let partnerCard, let data = Data(base64Encoded: partnerCard) else { return nil }
        return ProfileCode.decoded(data)
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
struct CloudChatMessage: Decodable {
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

@MainActor
protocol SecureChatRepository {
    var scope: String { get }
    func userID() async throws -> UUID
    func currentMatch() async throws -> CloudChatMatch?
    func isClosed(_ matchID: UUID) async throws -> Bool
    func bundles(_ matchID: UUID) async throws -> [CloudChatBundle]
    func register(_ matchID: UUID, deviceID: UUID, key: Data, replace: Bool) async throws
    func messages(_ matchID: UUID, after: Int64?) async throws -> [CloudChatMessage]
    func send(_ matchID: UUID, pending: ChatPendingMessage) async throws
    func end(_ matchID: UUID, reason: String) async throws
    func report(_ matchID: UUID, reason: String, details: String) async throws
    func report(_ matchID: UUID, reason: String, details: String, endMatch: Bool) async throws
    func shareCard(_ matchID: UUID, card: String) async throws
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws
}

extension SecureChatRepository {
    func report(_ matchID: UUID, reason: String, details: String, endMatch: Bool) async throws {
        try await report(matchID, reason: reason, details: details)
        if endMatch { try await end(matchID, reason: "blocked") }
    }
    func shareCard(_ matchID: UUID, card: String) async throws {}
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws {}
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
        try await client.rpc("current_chat_match").execute().value
    }
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
        let _: Int64 = try await client.rpc("send_encrypted_message",params:[
            "p_match_id":matchID.uuidString,"p_client_message_id":pending.id.uuidString,
            "p_sender_device_id":pending.senderDeviceID.uuidString,"p_recipient_device_id":pending.recipientDeviceID.uuidString,
            "p_ciphertext":pending.ciphertext,"p_protocol_version":ChatCryptography.protocolVersion]).execute().value
    }
    func end(_ matchID: UUID, reason: String) async throws {
        try await client.rpc("end_match",params:["p_match_id":matchID.uuidString,"p_reason":reason]).execute()
    }
    func report(_ matchID: UUID, reason: String, details: String) async throws {
        try await report(matchID, reason: reason, details: details, endMatch: false)
    }
    func report(_ matchID: UUID, reason: String, details: String, endMatch: Bool) async throws {
        struct Params: Encodable { let p_match_id: UUID; let p_reason: String; let p_details: String; let p_end_match: Bool }
        try await client.rpc("report_match",params:Params(p_match_id:matchID,p_reason:reason,p_details:details,p_end_match:endMatch)).execute()
    }
    func shareCard(_ matchID: UUID, card: String) async throws {
        try await client.rpc("share_match_card",params:["p_match_id":matchID.uuidString,"p_card":card]).execute()
    }
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws {
        struct Params: Encodable { let p_match_id: UUID; let p_message_id: Int64 }
        try await client.rpc("mark_chat_read",params:Params(p_match_id:matchID,p_message_id:messageID)).execute()
    }
}
