import CoreLocation
import XCTest
@testable import Stop_Swiping

/// A broken automatic match stays under My matches with its conversation,
/// and reports against this account come back from the server as strikes.
@MainActor
final class BrokenMatchTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func testBrokenMatchDecodesWhyAndWhenItEnded() throws {
        let json = """
        {"id":"\(UUID())","partner_id":"\(UUID())","partner_name":"","own_score":80,"partner_score":84,
         "matched_at":"2026-11-14T16:24:00Z","ended_at":"2026-11-15T09:00:00Z","end_reason":"profile_deleted",
         "ended_by_me":false,"partner_card":null,"unread_count":0}
        """
        let match = try decoder().decode(CloudChatMatch.self, from: Data(json.utf8))
        XCTAssertFalse(match.isActive)
        XCTAssertEqual(match.endReason, .profileDeleted)
        XCTAssertFalse(match.endedByMe)
    }

    func testActiveMatchWithoutEndFieldsStaysActive() throws {
        let json = """
        {"id":"\(UUID())","partner_id":"\(UUID())","partner_name":"Mila","own_score":80,"partner_score":84}
        """
        let match = try decoder().decode(CloudChatMatch.self, from: Data(json.utf8))
        XCTAssertTrue(match.isActive)
        XCTAssertNil(match.endReason)
    }

    func testModerationStatusShowsEachNewStrikeOnce() throws {
        let warned = try decoder().decode(ModerationStatus.self, from: Data("""
        {"strikes":1,"strikes_seen":0,"suspended_until":null,"banned":false}
        """.utf8))
        XCTAssertTrue(warned.hasUnseenNotice)
        XCTAssertFalse(warned.isSuspended())

        let blocked = try decoder().decode(ModerationStatus.self, from: Data("""
        {"strikes":2,"strikes_seen":2,"suspended_until":"2099-01-01T00:00:00Z","banned":false}
        """.utf8))
        XCTAssertFalse(blocked.hasUnseenNotice)
        XCTAssertTrue(blocked.isSuspended())

        let banned = ModerationStatus(strikes: 3, strikesSeen: 2, suspendedUntil: nil, banned: true)
        XCTAssertTrue(banned.hasUnseenNotice)
        XCTAssertFalse(banned.isSuspended(), "A ban is not a temporary block")
    }

    func testSavedMatchesFromBeforeKeepDecoding() throws {
        let snapshot = MatchSnapshot(matchedAt: Date(), you: Self.profile("Emma"), them: Self.profile("Mila"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "ended")
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.isBroken)
    }

    func testBrokenMatchKeepsThePartnersCardAfterItLeavesTheServer() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BrokenMatchTests-\(UUID())"))
        let card = try XCTUnwrap(ProfileCode.card(for: Self.profile("Mila").sharedCopy(today: .today())))
        let id = UUID(), partner = UUID()
        let repository = HistoryRepository()
        repository.history = [CloudChatMatch(id: id, partnerID: partner, partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                             matchedAt: Date(), partnerCard: card, endedAt: Date(), endReason: .broken)]
        let center = LiveMatchCenter(repository: repository, defaults: defaults)
        await center.loadHistory()
        XCTAssertEqual(center.pastMatches.map(\.id), [id])

        // The partner deletes their account: the server no longer has a card or name.
        repository.history = [CloudChatMatch(id: id, partnerID: partner, partnerName: "", ownScore: 80, partnerScore: 84,
                                             matchedAt: Date(), endedAt: Date(), endReason: .profileDeleted)]
        await center.loadHistory()
        let match = try XCTUnwrap(center.pastMatches.first)
        XCTAssertEqual(center.displayName(for: match), "Mila")
        let snapshot = center.snapshot(of: match, fallbackYou: Self.profile("Emma"))
        XCTAssertEqual(snapshot.them.displayName, "Mila")
        XCTAssertTrue(snapshot.isBroken)
        XCTAssertEqual(snapshot.ended?.reason, .profileDeleted)
        XCTAssertTrue(snapshot.report.isMatch, "A broken match still shows the heart the two once had")

        let chat = try XCTUnwrap(center.historyChat(for: match))
        XCTAssertTrue(chat.conversation.isClosed)
        XCTAssertFalse(chat.canSend)
    }

    /// After a hard close the app opens on the active match straight away,
    /// before the server has answered, and forgets it once the server does.
    func testActiveMatchIsThereAtLaunchBeforeTheServerAnswers() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BrokenMatchTests-\(UUID())"))
        let repository = HistoryRepository()
        let id = UUID()
        repository.current = CloudChatMatch(id: id, partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                             matchedAt: Date(), unreadCount: 2)
        let first = LiveMatchCenter(repository: repository, defaults: defaults)
        XCTAssertNil(first.match)
        await first.refresh(ownProfile: Self.profile("Emma"))
        XCTAssertEqual(first.match?.id, id)

        let relaunched = LiveMatchCenter(repository: repository, defaults: defaults)
        XCTAssertEqual(relaunched.match, repository.current)
        XCTAssertEqual(relaunched.chat?.conversation.matchID, id)
        XCTAssertNotNil(relaunched.snapshot(fallbackYou: Self.profile("Emma")))

        // The match ended while the app was closed.
        repository.current = nil
        await relaunched.refresh(ownProfile: Self.profile("Emma"))
        XCTAssertNil(relaunched.match)
        XCTAssertNil(LiveMatchCenter(repository: repository, defaults: defaults).match)

        // Signing out leaves nothing for the next account.
        repository.current = CloudChatMatch(id: id, partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84)
        await relaunched.refresh(ownProfile: Self.profile("Emma"))
        LiveMatchCenter.clearCache(defaults: defaults)
        XCTAssertNil(LiveMatchCenter(repository: repository, defaults: defaults).match)
        XCTAssertNil(LiveMatchCenter(repository: nil, defaults: defaults).match)
    }

    private static func profile(_ name: String) -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        state.displayName = name
        state.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        state.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        state.heightCentimeters = 182
        state.gender = .woman
        state.partnerGenders = [.woman]
        state.languages = ["nl", "en"]
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        state.searchRadiusKilometers = 40
        var lifestyle = state.lifestyle
        lifestyle.hasChildren = false
        lifestyle.openToPartnerWithChildren = true
        lifestyle.futureChildren = .notSure
        for question in CompatibilityScaleQuestion.all {
            lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 3)
        }
        state.lifestyle = lifestyle
        state.completedAt = Date()
        return state
    }
}

@MainActor
private final class HistoryRepository: SecureChatRepository {
    let scope = "history-test-" + UUID().uuidString
    var history: [CloudChatMatch] = []
    var current: CloudChatMatch?
    func userID() async throws -> UUID { UUID() }
    func currentMatch() async throws -> CloudChatMatch? { current }
    func isClosed(_ matchID: UUID) async throws -> Bool { true }
    func bundles(_ matchID: UUID) async throws -> [CloudChatBundle] { [] }
    func register(_ matchID: UUID, deviceID: UUID, key: Data, replace: Bool) async throws {}
    func messages(_ matchID: UUID, after: Int64?) async throws -> [CloudChatMessage] { [] }
    func send(_ matchID: UUID, pending: ChatPendingMessage) async throws {}
    func breakMatch(_ matchID: UUID) async throws {}
    func report(_ matchID: UUID, reason: String, details: String) async throws {}
    func matchHistory() async throws -> [CloudChatMatch] { history }
}
