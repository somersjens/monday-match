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
/// for 7 days, 3 bans the account (and the phones it used). An administrator
/// can also ban directly. "May be under 18" is no strike: it locks the account
/// until the person proves their age. The newest report can always be
/// objected to (202611200007_report_objections.sql, 202611200009).
nonisolated struct ModerationStatus: Codable, Equatable {
    /// Where an objection to a report stands.
    enum Objection: String, Codable, Equatable {
        case pending, approved, rejected
    }

    /// The newest report that counts against this account.
    struct LatestReport: Codable, Equatable, Identifiable {
        let id: UUID
        /// A `ReportReason` raw value.
        let reason: String
        let objection: Objection?
        var reportReason: ReportReason? { ReportReason(rawValue: reason) }
    }

    /// Why the account is banned.
    enum BanReason: String, Codable, Equatable {
        /// Three strikes.
        case strikes
        /// An administrator banned the account directly.
        case direct
        /// This phone was used by a banned account.
        case device
    }

    /// The newest "may be under 18" report that still stands: the account is
    /// locked until the person proves their age.
    struct AgeCheck: Codable, Equatable, Identifiable {
        let id: UUID
        /// An administrator's demo report: shows the same, never locks.
        var isDemo = false
        /// Nil until the person sent their proof or message.
        let objection: Objection?
        enum CodingKeys: String, CodingKey { case id, isDemo = "is_demo", objection }
        init(id: UUID, isDemo: Bool = false, objection: Objection?) {
            self.id = id; self.isDemo = isDemo; self.objection = objection
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            isDemo = (try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? false
            objection = try? c.decodeIfPresent(Objection.self, forKey: .objection)
        }
        /// The report, as the verification screen takes it.
        var report: LatestReport { LatestReport(id: id, reason: ReportReason.underage.rawValue, objection: objection) }
    }

    /// A decided objection whose outcome this person has not read yet.
    struct ObjectionResult: Codable, Equatable {
        let id: UUID
        let decision: Objection
        let reason: String
    }

    let strikes: Int
    let strikesSeen: Int
    let suspendedUntil: Date?
    let banned: Bool
    var banReason: BanReason?
    var latestReport: LatestReport?
    var objectionResult: ObjectionResult?
    var ageCheck: AgeCheck?
    /// Waiting to prove their age: no matching, no chat.
    var ageLocked = false
    /// This account decides objections (matching_private.admins).
    var isAdmin = false
    /// Objections and reviews waiting for an administrator; 0 for everyone else.
    var adminPending = 0

    enum CodingKeys: String, CodingKey {
        case strikes, strikesSeen = "strikes_seen", suspendedUntil = "suspended_until", banned
        case banReason = "ban_reason", latestReport = "latest_report", objectionResult = "objection_result"
        case ageCheck = "age_check", ageLocked = "age_locked"
        case isAdmin = "is_admin", adminPending = "admin_pending"
    }
    init(strikes: Int, strikesSeen: Int, suspendedUntil: Date?, banned: Bool, banReason: BanReason? = nil,
         latestReport: LatestReport? = nil, objectionResult: ObjectionResult? = nil,
         ageCheck: AgeCheck? = nil, ageLocked: Bool = false,
         isAdmin: Bool = false, adminPending: Int = 0) {
        self.strikes = strikes; self.strikesSeen = strikesSeen; self.suspendedUntil = suspendedUntil; self.banned = banned
        self.banReason = banReason
        self.latestReport = latestReport; self.objectionResult = objectionResult
        self.ageCheck = ageCheck; self.ageLocked = ageLocked
        self.isAdmin = isAdmin; self.adminPending = adminPending
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strikes = try c.decodeIfPresent(Int.self, forKey: .strikes) ?? 0
        strikesSeen = try c.decodeIfPresent(Int.self, forKey: .strikesSeen) ?? 0
        suspendedUntil = try? c.decodeIfPresent(Date.self, forKey: .suspendedUntil)
        banned = try c.decodeIfPresent(Bool.self, forKey: .banned) ?? false
        banReason = try? c.decodeIfPresent(BanReason.self, forKey: .banReason)
        latestReport = try? c.decodeIfPresent(LatestReport.self, forKey: .latestReport)
        objectionResult = try? c.decodeIfPresent(ObjectionResult.self, forKey: .objectionResult)
        ageCheck = try? c.decodeIfPresent(AgeCheck.self, forKey: .ageCheck)
        ageLocked = (try? c.decodeIfPresent(Bool.self, forKey: .ageLocked)) ?? false
        isAdmin = (try? c.decodeIfPresent(Bool.self, forKey: .isAdmin)) ?? false
        adminPending = (try? c.decodeIfPresent(Int.self, forKey: .adminPending)) ?? 0
    }

    func isSuspended(now: Date = Date()) -> Bool { !banned && (suspendedUntil.map { $0 > now } ?? false) }
    /// A new strike this person has not acknowledged yet.
    var hasUnseenNotice: Bool { strikes > strikesSeen }
    /// The newest report can still be objected to.
    var canObject: Bool { latestReport != nil && latestReport?.objection == nil }
    /// Something is waiting on an administrator, for this person or for them
    /// as an administrator: worth asking the server more often.
    var awaitsDecision: Bool { latestReport?.objection == .pending || ageCheck?.objection == .pending || isAdmin }
    /// The person must still prove their age; until then nothing else can be done.
    var needsAgeProof: Bool { ageCheck != nil && ageCheck?.objection == nil }
    /// No matching and no chat: banned, blocked for 7 days, or waiting to prove their age.
    func isLocked(now: Date = Date()) -> Bool { banned || isSuspended(now: now) || ageLocked }
}

/// One line of a conversation copy sent with a report, oldest first.
nonisolated struct ReportChatLine: Codable, Equatable {
    enum Author: String, Codable { case reporter, reported }
    let from: Author
    let at: Date
    let text: String

    /// The conversation as this phone has it, newest messages kept when it
    /// is longer than the server takes (256 KB).
    @MainActor
    static func copy(of messages: [ChatMessage], limit: Int = 240_000) -> [ReportChatLine] {
        var lines: [ReportChatLine] = []
        var size = 2
        for message in messages.reversed() {
            let from: Author
            switch message.sender {
            case .currentUser: from = .reporter
            case .match: from = .reported
            case .system: continue
            }
            // JSON escaping can grow the text; count it generously.
            let cost = message.text.utf8.count * 2 + 80
            if size + cost > limit { break }
            size += cost
            lines.append(ReportChatLine(from: from, at: message.sentAt, text: message.text))
        }
        return lines.reversed()
    }
}

/// What the phone read from a passport or ID card to dispute "may be under
/// 18". Only these facts leave the phone, never the photo.
nonisolated struct ReportIDCheck: Codable, Equatable {
    /// First letter of the first given name.
    let initial: String
    /// First letter of every given name: "Jan Pieter" may go by Pieter.
    var initials: [String]? = nil
    /// yyyy-MM-dd.
    let birthDate: String
    let expires: String?
    /// "P" passport, "I"/"ID" identity card.
    let document: String
    let checkDigits: Bool
    enum CodingKeys: String, CodingKey {
        case initial, initials, birthDate = "birth_date", expires, document, checkDigits = "check_digits"
    }
}

/// How someone reported as "may be under 18" confirms their age.
nonisolated enum AgeProof: Encodable, Equatable {
    /// What the phone read from their passport or ID card.
    case document(ReportIDCheck)
    /// The document could not be read: they added a photo of it, which stays
    /// on the phone. Only that a photo was added is sent, never ID details.
    case manualReview

    func encode(to encoder: Encoder) throws {
        switch self {
        case .document(let check):
            try check.encode(to: encoder)
        case .manualReview:
            var container = encoder.singleValueContainer()
            try container.encode(["manual_review": true, "photo_attached": true])
        }
    }
}

/// An objection as an administrator sees it: the report first, then the
/// objection (202611200007 admin_objections).
nonisolated struct AdminObjection: Decodable, Identifiable, Equatable {
    struct Report: Decodable, Equatable {
        let id: UUID
        let reason: String
        let details: String
        let createdAt: Date
        let chatCopy: [ReportChatLine]?
        let endedMatch: Bool
        /// 0 "under 18" (a lock, not a strike), 1 warning, 2 a 7-day block, 3 or more a ban.
        let strike: Int
        /// An administrator reported the demo match: about themself, never a lock.
        let isDemo: Bool
        enum CodingKeys: String, CodingKey {
            case id, reason, details, createdAt = "created_at", chatCopy = "chat_copy", endedMatch = "ended_match", strike
            case isDemo = "is_demo"
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            reason = try c.decode(String.self, forKey: .reason)
            details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
            createdAt = try c.decode(Date.self, forKey: .createdAt)
            chatCopy = try? c.decodeIfPresent([ReportChatLine].self, forKey: .chatCopy)
            endedMatch = try c.decodeIfPresent(Bool.self, forKey: .endedMatch) ?? false
            strike = try c.decodeIfPresent(Int.self, forKey: .strike) ?? 1
            isDemo = (try? c.decodeIfPresent(Bool.self, forKey: .isDemo)) ?? false
        }
    }

    /// The server's reading of the document against the profile.
    struct IDCheck: Decodable, Equatable {
        let initial: String?
        /// Every given name's first letter (202611200009); older checks have only `initial`.
        let initials: [String]?
        let birthDate: String?
        let expires: String?
        let document: String?
        let checkDigits: Bool?
        let adult: Bool?
        let expired: Bool?
        let profileInitial: String?
        let profileBirthDate: String?
        let initialMatches: Bool?
        let birthDateMatches: Bool?
        /// "Request manual review": a photo was added on their phone, no ID details sent.
        let manualReview: Bool?
        enum CodingKeys: String, CodingKey {
            case manualReview = "manual_review"
            case initial, initials, birthDate = "birth_date", expires, document, checkDigits = "check_digits", adult, expired
            case profileInitial = "profile_initial", profileBirthDate = "profile_birth_date"
            case initialMatches = "initial_matches", birthDateMatches = "birth_date_matches"
        }
    }

    let id: UUID
    let createdAt: Date
    let message: String
    let idCheck: IDCheck?
    let displayName: String?
    /// "Under 18" was disputed with a matching document before and approved
    /// automatically; this second time an administrator decides.
    let ageProvenBefore: Bool
    /// Approved by itself then, unless an administrator decides first.
    let autoDecidesAt: Date?
    let report: Report

    enum CodingKeys: String, CodingKey {
        case id, createdAt = "created_at", message, idCheck = "id_check", displayName = "display_name", report
        case ageProvenBefore = "age_proven_before", autoDecidesAt = "auto_decides_at"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        idCheck = try? c.decodeIfPresent(IDCheck.self, forKey: .idCheck)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        ageProvenBefore = (try? c.decodeIfPresent(Bool.self, forKey: .ageProvenBefore)) ?? false
        autoDecidesAt = try? c.decodeIfPresent(Date.self, forKey: .autoDecidesAt)
        report = try c.decode(Report.self, forKey: .report)
    }
}

/// "Concerning offline behavior", waiting for an administrator to keep it
/// as a regular warning or ban the account directly (202611200009 admin_reviews).
nonisolated struct AdminReview: Decodable, Identifiable, Equatable {
    /// The same fields as an objection's report, at the top level.
    let report: AdminObjection.Report
    let displayName: String?
    /// Kept as a regular warning by itself then, unless decided first.
    let autoDecidesAt: Date?
    var id: UUID { report.id }

    enum CodingKeys: String, CodingKey { case displayName = "display_name", autoDecidesAt = "auto_decides_at" }
    init(from decoder: Decoder) throws {
        report = try AdminObjection.Report(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        autoDecidesAt = try? c.decodeIfPresent(Date.self, forKey: .autoDecidesAt)
    }
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
    /// With a copy of the conversation, made on this phone (messages are
    /// end-to-end encrypted). Read by an administrator only on an objection.
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool,
                chatCopy: [ReportChatLine]?) async throws
    func shareCard(_ matchID: UUID, card: String) async throws
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws
    /// Every match this account has had, newest first, active and broken.
    func matchHistory() async throws -> [CloudChatMatch]
    func moderation() async throws -> ModerationStatus
    func acknowledgeModeration() async throws
    /// Objects to the newest report against this account.
    func objectToReport(_ reportID: UUID, message: String, proof: AgeProof?) async throws
    /// Administrators only: reports the demo match as a report against this
    /// account itself, to try the warning, the objection and the decision.
    func reportDemo(reason: String, details: String, chatCopy: [ReportChatLine]?) async throws
    /// Administrators only: every open objection, oldest first.
    func adminObjections() async throws -> [AdminObjection]
    /// Administrators only: approve withdraws the report, reject keeps it;
    /// reject with `ban` also bans the account directly.
    func decideObjection(_ objectionID: UUID, approve: Bool, ban: Bool) async throws
    /// Administrators only: "concerning offline behavior" waiting for a decision.
    func adminReviews() async throws -> [AdminReview]
    /// Administrators only: keep as a regular warning, or ban directly.
    func reviewReport(_ reportID: UUID, ban: Bool) async throws
    /// The partner's matching photo; Storage only allows it during an active match.
    func partnerPhoto(path: String) async throws -> Data
    /// Removes an ended match from this account's My matches. The other
    /// person keeps it until they delete it too.
    func deleteMatch(_ matchID: UUID) async throws
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
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool,
                chatCopy: [ReportChatLine]?) async throws {
        try await report(matchID, reason: reason, details: details, breakMatch: breakMatch)
    }
    func objectToReport(_ reportID: UUID, message: String, proof: AgeProof?) async throws {}
    func reportDemo(reason: String, details: String, chatCopy: [ReportChatLine]?) async throws {}
    func adminObjections() async throws -> [AdminObjection] { [] }
    func decideObjection(_ objectionID: UUID, approve: Bool, ban: Bool) async throws {}
    func adminReviews() async throws -> [AdminReview] { [] }
    func reviewReport(_ reportID: UUID, ban: Bool) async throws {}
    func shareCard(_ matchID: UUID, card: String) async throws {}
    func markRead(_ matchID: UUID, upTo messageID: Int64) async throws {}
    func matchHistory() async throws -> [CloudChatMatch] { [] }
    func moderation() async throws -> ModerationStatus { .init(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: false) }
    func acknowledgeModeration() async throws {}
    func partnerPhoto(path: String) async throws -> Data { throw CancellationError() }
    func deleteMatch(_ matchID: UUID) async throws {}
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
        return try await client.rpc("current_match", params: ["p_known_card": knownCard.uuidString]).execute().value
    }
    func poll(_ matchID: UUID, after: Int64?) async throws -> ChatPoll {
        struct Params: Encodable { let p_match_id: UUID; let p_after: Int64? }
        return try await client.rpc("chat_poll", params: Params(p_match_id: matchID, p_after: after)).execute().value
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
        try await report(matchID, reason: reason, details: details, breakMatch: breakMatch, chatCopy: nil)
    }
    func report(_ matchID: UUID, reason: String, details: String, breakMatch: Bool,
                chatCopy: [ReportChatLine]?) async throws {
        struct Params: Encodable {
            let p_match_id: UUID; let p_reason: String; let p_details: String; let p_break_match: Bool
            let p_chat_copy: [ReportChatLine]?
        }
        let copy = chatCopy.flatMap { $0.isEmpty ? nil : $0 }
        try await client.rpc("report_partner",params:Params(p_match_id:matchID,p_reason:reason,p_details:details,
            p_break_match:breakMatch,p_chat_copy:copy)).execute()
    }
    func matchHistory() async throws -> [CloudChatMatch] {
        try await client.rpc("my_matches").execute().value
    }
    func moderation() async throws -> ModerationStatus {
        nonisolated struct Status: Decodable {
            let moderation: ModerationStatus
            let is_admin: Bool?
            let admin_pending: Int?
        }
        let status: Status = try await client.rpc("matching_status").execute().value
        var moderation = status.moderation
        moderation.isAdmin = status.is_admin ?? false
        moderation.adminPending = status.admin_pending ?? 0
        return moderation
    }
    func acknowledgeModeration() async throws {
        try await client.rpc("acknowledge_moderation").execute()
    }
    func objectToReport(_ reportID: UUID, message: String, proof: AgeProof?) async throws {
        struct Params: Encodable { let p_report_id: UUID; let p_message: String; let p_id_check: AgeProof? }
        try await client.rpc("object_to_report", params: Params(p_report_id: reportID, p_message: message,
                                                                 p_id_check: proof)).execute()
    }
    func reportDemo(reason: String, details: String, chatCopy: [ReportChatLine]?) async throws {
        struct Params: Encodable { let p_reason: String; let p_details: String; let p_chat_copy: [ReportChatLine]? }
        let copy = chatCopy.flatMap { $0.isEmpty ? nil : $0 }
        try await client.rpc("report_demo", params: Params(p_reason: reason, p_details: details, p_chat_copy: copy)).execute()
    }
    func adminObjections() async throws -> [AdminObjection] {
        try await client.rpc("admin_objections").execute().value
    }
    func decideObjection(_ objectionID: UUID, approve: Bool, ban: Bool) async throws {
        struct Params: Encodable { let p_objection_id: UUID; let p_approve: Bool; let p_ban: Bool }
        try await client.rpc("admin_decide_objection", params: Params(p_objection_id: objectionID, p_approve: approve,
                                                                       p_ban: ban)).execute()
    }
    func adminReviews() async throws -> [AdminReview] {
        try await client.rpc("admin_reviews").execute().value
    }
    func reviewReport(_ reportID: UUID, ban: Bool) async throws {
        struct Params: Encodable { let p_report_id: UUID; let p_ban: Bool }
        try await client.rpc("admin_review_report", params: Params(p_report_id: reportID, p_ban: ban)).execute()
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
    func deleteMatch(_ matchID: UUID) async throws {
        try await client.rpc("delete_match", params: ["p_match_id": matchID.uuidString]).execute()
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
