import CoreLocation
import XCTest
@testable import Stop_Swiping

@MainActor
final class MatchChatTests: XCTestCase {
    func testDemoConversationStartsWithAnUnreadHiAndAnswersEveryMessage() async throws {
        let chat = ChatViewModel.demo(matchID: UUID(), name: "Mila")
        XCTAssertTrue(chat.isDemo)
        XCTAssertEqual(chat.conversation.messages.map(\.text), ["Hi"])
        XCTAssertEqual(chat.unreadMessages.count, 1)

        chat.markAllRead()
        XCTAssertTrue(chat.unreadMessages.isEmpty)

        chat.draftMessage = "Hey Mila"
        XCTAssertTrue(chat.canSend)
        chat.sendMessage()
        XCTAssertEqual(chat.conversation.messages.last?.text, "Hey Mila")
        XCTAssertEqual(chat.draftMessage, "")
        let sent = try XCTUnwrap(chat.conversation.messages.last)
        XCTAssertFalse(chat.isReadByPartner(sent))

        try await Task.sleep(for: .seconds(2.5))
        XCTAssertEqual(chat.conversation.messages.map(\.text), ["Hi", "Hey Mila", "Hi"])
        XCTAssertFalse(chat.isPartnerTyping)
        XCTAssertTrue(chat.isReadByPartner(sent), "A reply means the message was read")
    }

    func testBreakingThroughAReportClosesTheDemoConversation() {
        let chat = ChatViewModel.demo(matchID: UUID(), name: "Mila")
        chat.submitReport(reason: .spam, details: "", endMatch: true)
        XCTAssertTrue(chat.conversation.isClosed)
        XCTAssertFalse(chat.canSend)
    }

    func testLiveMatchDecodesTheServerRowAndTheSharedCard() throws {
        let profile = Self.profile(name: "Mila")
        let card = try XCTUnwrap(ProfileCode.encoded(profile.sharedCopy(today: .today()))).base64EncodedString()
        let id = UUID(), partner = UUID()
        let json = """
        {"id":"\(id)","partner_id":"\(partner)","partner_name":"Mila","own_score":88,"partner_score":89,
         "matched_at":"2026-11-14T16:24:00Z","partner_card":"\(card)","unread_count":2,
         "last_message_at":null,"partner_read_at":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let match = try decoder.decode(CloudChatMatch.self, from: Data(json.utf8))
        XCTAssertEqual(match.id, id)
        XCTAssertEqual(match.unreadCount, 2)
        XCTAssertEqual(match.average, 89)
        XCTAssertNotNil(match.matchedAt)
        XCTAssertEqual(match.partnerProfile?.displayName, "Mila")
    }

    func testServerScoresDecideALiveMatch() {
        let you = Self.profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let them = Self.profile(name: "Mila")
        let snapshot = MatchSnapshot(matchedAt: Date(), you: you, them: them,
                                     fixedScores: .init(yours: 88, theirs: 89))
        XCTAssertTrue(snapshot.isLive)
        XCTAssertEqual(snapshot.report.score(.yours), 88)
        XCTAssertEqual(snapshot.report.score(.theirs), 89)
        XCTAssertEqual(snapshot.report.average, 89)
        XCTAssertTrue(snapshot.report.isMatch)
    }

    func testRingsTurnFromRestAndKeepGoing() {
        typealias Chat = WelcomeLightMatch.Chat
        XCTAssertEqual(Chat.progress(elapsed: 0), 0)
        XCTAssertEqual(Chat.progress(elapsed: Chat.morphDuration), 1)
        XCTAssertEqual(Chat.orbitAngle(elapsed: Chat.orbitStart), 0)
        // Speed eases in: the first moments turn far less than full speed would.
        let early = Chat.orbitAngle(elapsed: Chat.orbitStart + 0.2)
        XCTAssertLessThan(early, 0.2 * 2 * .pi / Chat.orbitPeriod * 0.1)
        // Afterwards one period is one full turn.
        let later = Chat.orbitStart + Chat.orbitRamp + 1
        XCTAssertEqual(Chat.orbitAngle(elapsed: later + Chat.orbitPeriod) - Chat.orbitAngle(elapsed: later),
                       2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(Chat.orbitAngle(elapsed: 10, reduceMotion: true), 0)
    }

    private static func profile(name: String, gender: GenderIdentity = .man,
                                partnerGenders: Set<GenderIdentity> = [.woman]) -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        state.displayName = name
        state.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        state.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        state.heightCentimeters = 182
        state.gender = gender
        state.partnerGenders = partnerGenders
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
