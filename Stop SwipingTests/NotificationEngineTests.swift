import UserNotifications
import XCTest
@testable import Stop_Swiping

/// The engine against a fake notification center: scheduling, automatic
/// cancellation, idempotency, consent changes, ended matches, routing and
/// analytics.
@MainActor
final class NotificationEngineTests: XCTestCase {
    private final class FakeCenter: NotificationCentering {
        var permission: NotificationPermissionState = .authorized
        var pending: [String: PlannedNotification] = [:]
        var deliveredItems: [(identifier: String, userInfo: [String: String])] = []
        var addCount = 0

        func authorization() async -> NotificationPermissionState { permission }
        func requestAuthorization() async -> Bool { permission = .authorized; return true }
        func pendingIdentifiers() async -> Set<String> { Set(pending.keys) }
        func delivered() async -> [(identifier: String, userInfo: [String: String])] { deliveredItems }
        func add(_ planned: PlannedNotification, calendar: Calendar) async throws {
            addCount += 1
            pending[planned.identifier] = planned
        }
        func removePending(_ identifiers: [String]) { identifiers.forEach { pending[$0] = nil } }
        func removeDelivered(_ identifiers: [String]) {}
        func registerCategories() {}

        /// The system fires everything due by `date`.
        func fire(until date: Date) {
            for (identifier, planned) in pending where planned.fireDate <= date {
                pending[identifier] = nil
                deliveredItems.append((identifier, ["kind": planned.kind.rawValue, "dedupe": planned.dedupeKey]))
            }
        }
    }

    private final class FakeRegistrar: PushDeviceRegistering {
        var registrations = 0
        var unregistrations = 0
        var languages: [AppLanguage] = []
        func register(deviceID: UUID, token: String, timeZone: String, language: AppLanguage,
                      preferences: NotificationPreferences) async throws {
            registrations += 1
            languages.append(language)
        }
        func unregister(deviceID: UUID) async throws { unregistrations += 1 }
    }

    private let day: TimeInterval = 86_400
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var center: FakeCenter!
    private var clock = Date()
    private var profile: ProfileCreationState?
    private var language = AppLanguage.english

    override func setUp() {
        super.setUp()
        suiteName = "NotificationEngineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        center = FakeCenter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        clock = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
        profile = completedProfile(consentedAt: clock.addingTimeInterval(-8 * day))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func completedProfile(consentedAt: Date?) -> ProfileCreationState {
        var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 16), applicationLanguage: "en")
        state.dateOfBirth = .init(year: 1994, month: 3, day: 2)
        state.completedAt = clock.addingTimeInterval(-10 * day)
        state.displayName = "Sam"
        state.hasUnderstoodExplanation = true
        state.profilePrivacyConsent = consentedAt.map {
            PrivacyConsentReceipt(version: PrivacyConsentKind.profile.version, acceptedAt: $0, languageCode: "en")
        }
        return state
    }

    private func makeEngine(registrar: PushDeviceRegistering? = nil) -> NotificationEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        let engine = NotificationEngine(center: center, loadProfile: { [unowned self] in profile }, defaults: defaults,
                                        registrar: registrar, calendar: calendar,
                                        language: { [unowned self] in language }, now: { [unowned self] in clock })
        engine.update(hasAccount: true, earlyAccessReminderAt: nil)
        return engine
    }

    private func ready(_ engine: NotificationEngine) async {
        await engine.refreshPermission()
        await engine.appBecameActive()
    }

    private var pendingKinds: Set<NotificationKind> { Set(center.pending.values.map(\.kind)) }

    private func match(id: UUID = UUID(), endedAt: Date? = nil, endedByMe: Bool = false) -> CloudChatMatch {
        CloudChatMatch(id: id, partnerID: UUID(), partnerName: "Alex", ownScore: 80, partnerScore: 82,
                       matchedAt: clock.addingTimeInterval(-2 * day), endedAt: endedAt,
                       endReason: endedAt == nil ? nil : .broken, endedByMe: endedByMe)
    }

    // MARK: - Scheduling and cancellation

    func testCompletingTheActionCancelsItsReminder() async {
        let engine = makeEngine()
        await ready(engine)
        XCTAssertTrue(pendingKinds.contains(.firstMatchmaking))

        engine.recordCompatibilityCheck()
        await engine.sync()
        XCTAssertFalse(pendingKinds.contains(.firstMatchmaking))
        XCTAssertTrue(pendingKinds.contains(.compatibilityMonthly))
        XCTAssertTrue(engine.ledger.events.contains { $0.name == .cancelled && $0.kind == .firstMatchmaking })
    }

    func testReplanningIsIdempotent() async {
        let engine = makeEngine()
        await ready(engine)
        let adds = center.addCount
        let pending = center.pending
        await engine.sync()
        await engine.sync()
        XCTAssertEqual(center.addCount, adds, "An unchanged plan must not touch the system's requests.")
        XCTAssertEqual(center.pending, pending)
    }

    func testADeliveredReminderIsNeverSentTwice() async throws {
        let engine = makeEngine()
        await ready(engine)
        let reminder = try XCTUnwrap(center.pending.values.first { $0.kind == .firstMatchmaking })

        clock = reminder.fireDate.addingTimeInterval(60)
        center.fire(until: clock)
        await engine.sync()
        XCTAssertTrue(engine.ledger.hasDelivered(reminder.dedupeKey))

        // Days later, still no exchange: the same reminder stays gone.
        clock = clock.addingTimeInterval(10 * day)
        center.deliveredItems = []
        await engine.appBecameActive()
        XCTAssertFalse(center.pending.values.contains { $0.dedupeKey == reminder.dedupeKey })
    }

    func testNothingIsScheduledWithoutPermission() async {
        center.permission = .denied
        let engine = makeEngine()
        await ready(engine)
        XCTAssertTrue(center.pending.isEmpty)
    }

    // MARK: - Consent

    func testWithdrawnConsentSwapsMatchingNudgesForAConsentReminder() async {
        let engine = makeEngine()
        await ready(engine)
        XCTAssertTrue(pendingKinds.contains(.firstMatchmaking))

        profile?.restartNextActions()
        engine.profileChanged()
        await engine.sync()
        XCTAssertEqual(pendingKinds, [.privacyRequired])

        profile?.profilePrivacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.profile.version,
                                                                acceptedAt: clock, languageCode: "en")
        await engine.sync()
        XCTAssertFalse(pendingKinds.contains(.privacyRequired))
    }

    func testOutdatedTermsAreNoticedOnceAndTimedFromThen() async throws {
        profile?.profilePrivacyConsent = PrivacyConsentReceipt(version: "2020-01-01.v1", acceptedAt: clock, languageCode: "en")
        let engine = makeEngine()
        await ready(engine)
        let first = try XCTUnwrap(center.pending.values.first { $0.kind == .privacyUpdated })
        clock = clock.addingTimeInterval(3_600)
        await engine.sync()
        // The timer started when the problem was first seen, not at every sync.
        XCTAssertEqual(center.pending[first.identifier]?.fireDate, first.fireDate)
    }

    // MARK: - Matches

    func testAMatchSeenInTheAppIsNeverNotifiedLater() async {
        let engine = makeEngine()
        await ready(engine)
        let current = match()
        engine.updateLiveMatch(current, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        XCTAssertTrue(engine.ledger.hasDelivered(NotificationEngine.matchKey(current.id)))
        await engine.sync()
        // With a match: a hello nudge instead of matchmaking reminders.
        XCTAssertTrue(pendingKinds.contains(.matchNoConversation))
        XCTAssertFalse(pendingKinds.contains(.firstMatchmaking))
    }

    func testAMatchEndedByThePartnerIsToldOnceInTheAppAndStopsItsReminders() async {
        let engine = makeEngine()
        await ready(engine)
        let id = UUID()
        let message = ChatMessage(sender: .match, text: "Hi", sentAt: clock.addingTimeInterval(-3_600))
        engine.updateLiveMatch(match(id: id), messages: [message], lastReadAt: nil, unsentIDs: [],
                               isConversationLoaded: true, history: [], isSuspended: false)
        await engine.sync()
        XCTAssertTrue(pendingKinds.contains(.messageUnanswered))

        let ended = match(id: id, endedAt: clock, endedByMe: false)
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [ended], isSuspended: false)
        await engine.sync()
        XCTAssertEqual(engine.notice?.kind, .matchEnded)
        XCTAssertEqual(engine.notice?.destination, .myMatches)
        XCTAssertFalse(pendingKinds.contains(.messageUnanswered))
        let text = (engine.notice?.title ?? "") + (engine.notice?.body ?? "")
        XCTAssertFalse(text.contains("Alex"))

        engine.notice = nil
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [ended], isSuspended: false)
        XCTAssertNil(engine.notice)
    }

    func testBreakingYourOwnMatchOrBeingSuspendedShowsNoNotice() async {
        let engine = makeEngine()
        let id = UUID()
        engine.updateLiveMatch(match(id: id), messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [match(id: id, endedAt: clock, endedByMe: true)], isSuspended: false)
        XCTAssertNil(engine.notice)

        let other = UUID()
        engine.updateLiveMatch(match(id: other), messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [match(id: other, endedAt: clock)], isSuspended: true)
        XCTAssertNil(engine.notice)
    }

    func testReadingTheChatCancelsTheUnreadReminder() async {
        let engine = makeEngine()
        await ready(engine)
        let current = match()
        let message = ChatMessage(sender: .match, text: "Hi", sentAt: clock.addingTimeInterval(-3_600))
        engine.updateLiveMatch(current, messages: [message], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        await engine.sync()
        XCTAssertTrue(pendingKinds.contains(.messageUnanswered))
        engine.updateLiveMatch(current, messages: [message], lastReadAt: message.sentAt, unsentIDs: [],
                               isConversationLoaded: true, history: [], isSuspended: false)
        await engine.sync()
        XCTAssertFalse(pendingKinds.contains(.messageUnanswered))
    }

    func testABackgroundMessagePushTurnsTheQuietReminderIntoAnUnreadOne() async {
        let engine = makeEngine()
        await ready(engine)
        let current = match()
        let messages = [ChatMessage(sender: .currentUser, text: "Hey", sentAt: clock.addingTimeInterval(-2 * day)),
                        ChatMessage(sender: .match, text: "Hi", sentAt: clock.addingTimeInterval(-day))]
        engine.updateLiveMatch(current, messages: messages, lastReadAt: clock, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        await engine.sync()
        XCTAssertTrue(pendingKinds.contains(.conversationQuiet))

        await engine.handleBackgroundPush(["kind": "message_new", "match_id": current.id.uuidString.lowercased()])
        XCTAssertTrue(pendingKinds.contains(.messageUnanswered))
        XCTAssertFalse(pendingKinds.contains(.conversationQuiet))
    }

    func testABackgroundMatchEndedPushStopsConversationReminders() async {
        let engine = makeEngine()
        await ready(engine)
        let current = match()
        engine.updateLiveMatch(current, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        await engine.sync()
        XCTAssertTrue(pendingKinds.contains(.matchNoConversation))
        await engine.handleBackgroundPush(["kind": "match_ended", "match_id": current.id.uuidString])
        XCTAssertFalse(pendingKinds.contains(.matchNoConversation))
    }

    func testServerPushesAlreadySeenAreRecorded() async {
        let engine = makeEngine()
        let id = UUID()
        center.deliveredItems = [("push-1", ["kind": "match_ended", "dedupe": "match_ended.\(id.uuidString.lowercased())"])]
        await ready(engine)
        // Seen on the lock screen: no second telling in the app.
        engine.updateLiveMatch(match(id: id), messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [match(id: id, endedAt: clock)], isSuspended: false)
        XCTAssertNil(engine.notice)
    }

    // MARK: - Presentation, routing, analytics

    func testMessagePushesAreHiddenWhileTheirChatIsOpen() {
        let engine = makeEngine()
        let payload = ["kind": "message_new", "dedupe": "message_new.x.1"]
        engine.isChatOpen = true
        XCTAssertEqual(engine.presentationOptions(identifier: "a", userInfo: payload), [])
        engine.isChatOpen = false
        XCTAssertEqual(engine.presentationOptions(identifier: "b", userInfo: payload), [.banner, .sound, .list])
    }

    func testOpeningANotificationRoutesAndCountsForItsVariant() {
        let engine = makeEngine()
        engine.handleResponse(action: UNNotificationDefaultActionIdentifier, userInfo: [
            "kind": "lower_standards", "variant": "lower_standards.b",
            "destination": NotificationDestination.autoMatching.url.absoluteString,
        ])
        XCTAssertEqual(engine.pendingDestination, .autoMatching)
        engine.handleResponse(action: UNNotificationDismissActionIdentifier,
                              userInfo: ["kind": "lower_standards", "variant": "lower_standards.a"])
        let summary = engine.ledger.variantSummary()
        XCTAssertEqual(summary["lower_standards.b"]?.opened, 1)
        XCTAssertEqual(summary["lower_standards.a"]?.dismissed, 1)
    }

    func testSwitchingOffNudgesIsRecordedAndCancelsThem() async {
        let engine = makeEngine()
        await ready(engine)
        XCTAssertTrue(pendingKinds.contains(.firstMatchmaking))
        var preferences = engine.preferences
        preferences.tipsAndNudges = false
        engine.setPreferences(preferences)
        await engine.sync()
        XCTAssertFalse(pendingKinds.contains(where: { $0.category.isNudge }))
        XCTAssertTrue(engine.ledger.events.contains { $0.name == .optedOut && $0.detail == "tips_and_nudges" })
        // Kept across launches.
        XCTAssertFalse(NotificationPreferencesStore(defaults: defaults).load().tipsAndNudges)
    }

    func testRevokedPermissionIsRecordedAndUnregistersPush() async {
        let registrar = FakeRegistrar()
        let engine = makeEngine(registrar: registrar)
        await ready(engine)
        center.permission = .denied
        await engine.refreshPermission()
        XCTAssertEqual(registrar.unregistrations, 1)
        XCTAssertTrue(engine.ledger.events.contains { $0.name == .permissionRevoked })
    }

    func testPushTokenIsRegisteredOnceAndAgainWhenPreferencesChange() async {
        let registrar = FakeRegistrar()
        let engine = makeEngine(registrar: registrar)
        await ready(engine)
        engine.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
        await engine.sync()
        await engine.sync()
        XCTAssertEqual(registrar.registrations, 1)
        var preferences = engine.preferences
        preferences.messagePreviews = false
        engine.setPreferences(preferences)
        await engine.sync()
        XCTAssertEqual(registrar.registrations, 2)
    }

    // MARK: - Language

    func testADutchAppGetsDutchNotificationsAndSwitchingRewritesThem() async throws {
        language = .dutch
        let engine = makeEngine()
        await ready(engine)
        let dutch = try XCTUnwrap(center.pending.values.first { $0.kind == .firstMatchmaking })
        XCTAssertTrue(dutch.variantID.contains(".nl."))
        XCTAssertTrue(NotificationCopy.dutch["first_matchmaking"]!.contains { $0.title == dutch.title })

        language = .english
        await engine.sync()
        let english = try XCTUnwrap(center.pending[dutch.identifier])
        XCTAssertFalse(english.variantID.contains(".nl."))
        XCTAssertTrue(NotificationCopy.english["first_matchmaking"]!.contains { $0.title == english.title })
        XCTAssertEqual(english.fireDate, dutch.fireDate, "Only the words change, not the timing.")
    }

    func testInAppNoticesSpeakTheAppsLanguage() async {
        language = .dutch
        let engine = makeEngine()
        let id = UUID()
        engine.updateLiveMatch(match(id: id), messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [], isSuspended: false)
        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: false,
                               history: [match(id: id, endedAt: clock)], isSuspended: false)
        let title = engine.notice?.title ?? ""
        XCTAssertTrue(NotificationCopy.dutch["match_ended"]!.contains { $0.title == title })
    }

    func testThePushRegistrationCarriesTheLanguageAndUpdatesWithIt() async {
        let registrar = FakeRegistrar()
        language = .dutch
        let engine = makeEngine(registrar: registrar)
        await ready(engine)
        engine.didRegister(deviceToken: Data(repeating: 0xab, count: 32))
        await engine.sync()
        language = .english
        await engine.sync()
        XCTAssertEqual(registrar.languages, [.dutch, .english])
    }

    func testWelcomeBackAfterAMonthAway() async {
        let engine = makeEngine()
        await ready(engine)
        XCTAssertNil(engine.notice)
        clock = clock.addingTimeInterval(31 * day)
        await engine.appBecameActive()
        XCTAssertEqual(engine.notice?.kind, .welcomeBack)
    }
}
