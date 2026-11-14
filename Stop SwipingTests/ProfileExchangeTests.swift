import CoreLocation
import XCTest
@testable import Stop_Swiping

@MainActor
final class ProfileExchangeTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 13)
    private var now: Date {
        BirthDateRules.calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 15))!
    }

    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    // MARK: - Weighting

    func testImportanceDoublesPerStepAndTheLowestDoesNotCount() {
        XCTAssertEqual((1...5).map(MatchWeighting.weight(importance:)), [0, 1, 2, 4, 8])
        XCTAssertEqual(MatchWeighting.weight(importance: 0), 0)
        XCTAssertEqual(MatchWeighting.weight(importance: 9), 8)

        // One very important miss outweighs three fairly important hits.
        let rows = [
            MatchReport.Row(step: .aloneTime, value: 1, wanted: 5, importance: 5),
            MatchReport.Row(step: .texting, value: 3, wanted: 3, importance: 3),
            MatchReport.Row(step: .calling, value: 3, wanted: 3, importance: 3),
            MatchReport.Row(step: .travel, value: 3, wanted: 3, importance: 3),
            MatchReport.Row(step: .pets, value: 1, wanted: 5, importance: 1)
        ]
        let expected: Double = 6.0 / 14 * 100
        XCTAssertEqual(MatchReport.score(rows), Int(expected.rounded()))
        XCTAssertEqual(MatchReport.score([]), 0)
        XCTAssertEqual(MatchReport.score([rows[4]]), 100, "Answers that don't matter never count against anyone.")
    }

    func testClosenessFallsEvenlyWithDistance() {
        let closeness = (1...5).map { MatchReport.Row(step: .aloneTime, value: $0, wanted: 1, importance: 3).closeness }
        XCTAssertEqual(closeness, [1, 0.75, 0.5, 0.25, 0])
    }

    func testStricterSubstanceLimitsCountMore() {
        XCTAssertEqual((0...5).map { MatchWeighting.substanceImportance(maximumLevel: $0, top: 5) }, [5, 4, 4, 3, 3, 2])
        XCTAssertEqual(MatchWeighting.substanceImportance(maximumLevel: 9, top: 5), 2)
    }

    func testSubstancesScoreByClosenessToYourOwnUse() {
        var you = profile(name: "Jens")
        // Everything else is irrelevant to you, so only alcohol decides.
        for question in CompatibilityScaleQuestion.all {
            you.lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 1)
        }
        you.lifestyle[.smoking] = SubstanceAnswer()
        you.lifestyle[.drugs] = SubstanceAnswer()
        you.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 3)

        var scores: [Int] = []
        for level in 0...5 {
            var them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
            them.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: level, partnerMaximumLevel: 5)
            let report = MatchReport(you: you, them: them, on: today)
            scores.append(report.yourScore)
            // At or under your limit a match stays possible; over it never.
            XCTAssertEqual(report.theirIssues.isEmpty, level <= 3, "level \(level)")
            XCTAssertEqual(report.isMatch, level <= 3, "level \(level)")
            let row = report.rows(.yours).first { $0.step == .alcohol }
            XCTAssertEqual(row, MatchReport.Row(step: .alcohol, value: level, wanted: 1, importance: 3, span: 5))
        }
        XCTAssertEqual(scores, [80, 100, 80, 60, 40, 20], "The closer to your own use, the better.")
    }

    func testSubstanceTargetNeverExceedsYourLimit() {
        var you = profile(name: "Jens")
        you.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 4, partnerMaximumLevel: 1)
        var them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        them.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 5)
        let row = MatchReport(you: you, them: them, on: today).rows(.yours).first { $0.step == .alcohol }
        XCTAssertEqual(row, MatchReport.Row(step: .alcohol, value: 1, wanted: 1, importance: 4, span: 5))
        XCTAssertEqual(row?.closeness, 1)
    }

    func testBothPhonesComputeTheSameReport() {
        let a = restrictive(profile(name: "Jens")).sharedCopy(today: today)
        let b = profile(name: "Emma", gender: .woman, partnerGenders: [.man]).sharedCopy(today: today)
        let onA = MatchReport(you: a, them: b, on: today)
        let onB = MatchReport(you: b, them: a, on: today)
        XCTAssertEqual(onA.yourScore, onB.theirScore)
        XCTAssertEqual(onA.theirScore, onB.yourScore)
        XCTAssertEqual(onA.average, onB.average)
        XCTAssertEqual(onA.isMatch, onB.isMatch)
        XCTAssertEqual(onA.theirIssues.count, onB.yourIssues.count)
    }

    // MARK: - What leaves the phone

    func testSharedCopyKeepsAnswersButNotBirthdayExactPlaceOrAppearance() throws {
        var state = restrictive(profile(name: "  Jens  "))
        state.currentStep = .pets
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05432, longitude: 3.71789),
                                          source: .device, placeName: "Gent")
        var auto = AutoMatchingSettings()
        auto.ownAttractiveness = 7
        auto.partnerMinimumAttractiveness = 6
        auto.isEnabled = true
        auto.photoID = UUID()
        state.autoMatching = auto

        let shared = state.sharedCopy(today: today)
        XCTAssertEqual(shared.displayName, "Jens")
        XCTAssertEqual(shared.age(on: today), state.age(on: today))
        XCTAssertEqual(shared.dateOfBirth, CalendarDate(year: 1996, month: 1, day: 1))
        XCTAssertEqual(shared.birthDateSelection, shared.dateOfBirth)
        XCTAssertEqual(shared.location?.latitude, 51.05)
        XCTAssertEqual(shared.location?.longitude, 3.72)
        XCTAssertEqual(shared.location?.placeName, "Gent")
        XCTAssertEqual(shared.autoMatching, AutoMatchingSettings())
        XCTAssertEqual(shared.currentStep, .dateOfBirth)
        XCTAssertEqual(shared.lifestyle, state.lifestyle)
        XCTAssertEqual(shared.religion, state.religion)
        XCTAssertEqual(shared.languages, state.languages)
        XCTAssertEqual(shared.partnerAgeRange, state.partnerAgeRange)
        XCTAssertEqual(shared.partnerHeightRange, state.partnerHeightRange)

        let wire = try XCTUnwrap(ProfileExchangeMessage.profile(shared).encoded())
        let text = try XCTUnwrap(String(data: wire, encoding: .utf8))
        XCTAssertFalse(text.contains("51.05432"))
        XCTAssertFalse(text.contains("\"month\":4"), "The real birthday stays on this phone.")
        XCTAssertLessThan(wire.count, ProfileExchangeMessage.maximumBytes / 4)
        XCTAssertEqual(ProfileExchangeMessage.decoded(wire), .profile(shared))
    }

    func testReceivedProfilesMustBeCompleteNamedAdults() {
        let valid = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        XCTAssertEqual(valid.receivedCopy(today: today)?.displayName, "Emma")

        var unnamed = valid
        unnamed.displayName = "   "
        XCTAssertNil(unnamed.receivedCopy(today: today))

        var unfinished = valid
        unfinished.completedAt = nil
        XCTAssertNil(unfinished.receivedCopy(today: today))

        var minor = valid
        minor.dateOfBirth = CalendarDate(year: 2010, month: 5, day: 2)
        XCTAssertNil(minor.receivedCopy(today: today))

        var impossible = valid
        impossible.dateOfBirth = CalendarDate(year: 1990, month: 2, day: 31)
        XCTAssertNil(impossible.receivedCopy(today: today))

        var odd = valid
        odd.displayName = String(repeating: "x", count: 200)
        odd.heightCentimeters = 9_000
        odd.searchRadiusKilometers = -4
        let cleaned = odd.receivedCopy(today: today)
        XCTAssertEqual(cleaned?.displayName.count, ProfileNameRules.maximumLength)
        XCTAssertEqual(cleaned?.heightCentimeters, HeightRules.range.upperBound)
        XCTAssertEqual(cleaned?.searchRadiusKilometers, SearchRadiusRules.range.lowerBound)
    }

    func testOversizedOrMalformedMessagesAreNotRead() {
        XCTAssertNil(ProfileExchangeMessage.decoded(Data(repeating: 0x20, count: ProfileExchangeMessage.maximumBytes + 1)))
        XCTAssertNil(ProfileExchangeMessage.decoded(Data("{\"steal\":{}}".utf8)))
        XCTAssertEqual(ProfileExchangeMessage.decoded(ProfileExchangeMessage.ready.encoded()!), .ready)
    }

    // MARK: - Negotiation

    /// Two phones wired back to back, delivering every message in order.
    @MainActor private struct Pair {
        var a: ProfileExchangeNegotiation
        var b: ProfileExchangeNegotiation
        var completedA: ProfileCreationState?
        var completedB: ProfileCreationState?
        var declinedA = 0
        var declinedB = 0
        var profilesSent = 0

        mutating func run(_ effects: [ProfileExchangeNegotiation.Effect], fromA: Bool) {
            for effect in effects {
                switch effect {
                case .send(let message, _):
                    if case .profile = message { profilesSent += 1 }
                    // Everything crosses as bytes, as it does between phones.
                    guard let data = message.encoded(), let decoded = ProfileExchangeMessage.decoded(data) else { continue }
                    if fromA {
                        run(b.received(decoded, from: "a"), fromA: false)
                    } else {
                        run(a.received(decoded, from: "b"), fromA: true)
                    }
                case .completed(_, let profile):
                    if fromA { completedA = profile } else { completedB = profile }
                case .declined:
                    if fromA { declinedA += 1 } else { declinedB += 1 }
                }
            }
        }
    }

    private func connectedPair(tokenA: Data? = nil, tokenB: Data? = nil) -> Pair {
        let jens = profile(name: "Jens")
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        var pair = Pair(a: ProfileExchangeNegotiation(profile: jens.sharedCopy(today: today), today: today),
                        b: ProfileExchangeNegotiation(profile: emma.sharedCopy(today: today), today: today))
        // Both connections are open before either greeting arrives.
        let greetingA = pair.a.connected("b", proximityToken: tokenA)
        let greetingB = pair.b.connected("a", proximityToken: tokenB)
        pair.run(greetingA, fromA: true)
        pair.run(greetingB, fromA: false)
        return pair
    }

    func testGreetingSharesOnlyNameAndToken() {
        let pair = connectedPair(tokenA: Data([1, 2, 3]))
        XCTAssertEqual(pair.a.peers["b"]?.name, "Emma")
        XCTAssertEqual(pair.b.peers["a"]?.name, "Jens")
        XCTAssertEqual(pair.b.peers["a"]?.proximityToken, Data([1, 2, 3]))
        XCTAssertNil(pair.a.peers["b"]?.proximityToken)
        XCTAssertEqual(pair.profilesSent, 0)
        XCTAssertNil(pair.completedA)
    }

    func testProfilesCrossOnlyOnceBothSidesAreReady() {
        var pair = connectedPair()
        pair.run(pair.a.confirm("b"), fromA: true)
        XCTAssertEqual(pair.profilesSent, 0, "One side being ready moves nothing.")
        XCTAssertEqual(pair.b.peers["a"]?.remoteReady, true)
        XCTAssertTrue(pair.a.confirm("b").isEmpty, "Being ready twice says nothing new.")

        pair.run(pair.b.confirm("a"), fromA: false)
        XCTAssertEqual(pair.profilesSent, 2)
        XCTAssertEqual(pair.completedA?.displayName, "Emma")
        XCTAssertEqual(pair.completedB?.displayName, "Jens")
        XCTAssertEqual(pair.completedA, pair.b.profile)
        XCTAssertEqual(pair.completedB, pair.a.profile)
    }

    func testAnUninvitedProfileIsIgnoredAndNothingIsSentBack() {
        var pair = connectedPair()
        let theirs = pair.b.profile
        XCTAssertTrue(pair.a.received(.profile(theirs), from: "b").isEmpty)
        // Even after they claim to be ready, this side hasn't agreed.
        XCTAssertTrue(pair.a.received(.ready, from: "b").isEmpty)
        XCTAssertTrue(pair.a.received(.profile(theirs), from: "b").isEmpty)
        XCTAssertTrue(pair.a.received(.profile(theirs), from: "stranger").isEmpty)
        XCTAssertEqual(pair.a.peers["b"]?.sentProfile, false)
    }

    func testDecliningTakesBackAnOfferAndFreesBothSides() {
        var pair = connectedPair()
        pair.run(pair.a.confirm("b"), fromA: true)
        pair.run(pair.b.decline("a"), fromA: false)
        XCTAssertEqual(pair.declinedA, 1)
        XCTAssertNil(pair.a.engagedPeer)
        XCTAssertEqual(pair.a.peers["b"]?.localReady, false)
        XCTAssertEqual(pair.profilesSent, 0)

        // Later, both can still agree.
        pair.run(pair.b.confirm("a"), fromA: false)
        pair.run(pair.a.confirm("b"), fromA: true)
        XCTAssertNotNil(pair.completedA)
        XCTAssertNotNil(pair.completedB)
    }

    func testOnlyOnePersonAtATime() {
        var a = ProfileExchangeNegotiation(profile: profile(name: "Jens").sharedCopy(today: today), today: today)
        _ = a.connected("b", proximityToken: nil)
        _ = a.connected("c", proximityToken: nil)
        _ = a.received(.hello(.init(name: "Emma", proximityToken: nil)), from: "b")
        _ = a.received(.hello(.init(name: "Sophie", proximityToken: nil)), from: "c")
        XCTAssertFalse(a.confirm("b").isEmpty)
        XCTAssertTrue(a.confirm("c").isEmpty, "Ready for Emma, so Sophie waits.")
        XCTAssertEqual(a.disconnected("b"), [.declined(peer: "b")])
        XCTAssertTrue(a.connected("c", proximityToken: nil).isEmpty, "A second connection event greets nobody twice.")
        XCTAssertFalse(a.confirm("c").isEmpty)
    }

    func testOtherVersionsAndNamelessPhonesAreLeftAlone() {
        var a = ProfileExchangeNegotiation(profile: profile(name: "Jens").sharedCopy(today: today), today: today)
        _ = a.connected("b", proximityToken: nil)
        XCTAssertTrue(a.confirm("b").isEmpty, "Nobody is ready for a phone that hasn't greeted.")
        _ = a.received(.hello(.init(version: 99, name: "Emma", proximityToken: nil)), from: "b")
        XCTAssertEqual(a.peers["b"]?.isCompatible, false)
        XCTAssertTrue(a.confirm("b").isEmpty)
        _ = a.connected("c", proximityToken: nil)
        _ = a.received(.hello(.init(name: "  ", proximityToken: nil)), from: "c")
        XCTAssertTrue(a.confirm("c").isEmpty)
    }

    func testAnInvalidProfileEndsTheExchangeWithoutAMatch() {
        var pair = connectedPair()
        var a = pair.a
        _ = a.confirm("b")
        _ = a.received(.ready, from: "b")
        var minor = pair.b.profile
        minor.dateOfBirth = CalendarDate(year: 2012, month: 1, day: 1)
        XCTAssertEqual(a.received(.profile(minor), from: "b"), [.declined(peer: "b")])
        XCTAssertNil(a.engagedPeer)
        pair.a = a
    }

    // MARK: - Held together

    func testPhonesCountAsTogetherOnlyAfterSeveralCloseReadings() {
        var gate = ProximityGate()
        XCTAssertFalse(gate.isTogether(afterReading: 0.05))
        XCTAssertFalse(gate.isTogether(afterReading: 0.08))
        XCTAssertFalse(gate.isTogether(afterReading: 0.60), "Moving apart starts over.")
        XCTAssertFalse(gate.isTogether(afterReading: 0.05))
        XCTAssertFalse(gate.isTogether(afterReading: nil))
        XCTAssertFalse(gate.isTogether(afterReading: 0.10))
        XCTAssertFalse(gate.isTogether(afterReading: 0.12))
        XCTAssertTrue(gate.isTogether(afterReading: 0.15))
        gate.reset()
        XCTAssertFalse(gate.isTogether(afterReading: 0.01))
        XCTAssertFalse(gate.isTogether(afterReading: -1))
        XCTAssertFalse(gate.isTogether(afterReading: .nan))
    }

    func testSessionStartsAndStopsCleanly() {
        let session = ProfileExchangeSession()
        XCTAssertFalse(session.isActive)
        var approved = profile(name: "Jens")
        approved.profilePrivacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.profile.version,
                                                               acceptedAt: now, languageCode: "en")
        session.start(profile: approved, today: today)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(session.people.isEmpty)
        session.confirm("nobody")
        session.decline("nobody")
        session.stop()
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.result)
        session.stop()
    }

    // MARK: - Fixtures

    private func profile(name: String, gender: GenderIdentity = .man,
                         partnerGenders: Set<GenderIdentity> = [.woman]) -> ProfileCreationState {
        var state = ProfileCreationState(today: today, applicationLanguage: "nl")
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
        for substance in Substance.allCases {
            lifestyle[substance] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 5)
        }
        for question in CompatibilityScaleQuestion.all {
            lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 3)
        }
        state.lifestyle = lifestyle
        state.completedAt = now
        return state
    }

    private func restrictive(_ profile: ProfileCreationState) -> ProfileCreationState {
        var state = profile
        state.lifestyle.futureChildren = .yes
        state.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 3, partnerMaximumLevel: 0)
        var religion = ReligionAnswers()
        religion.own = .christian
        religion.acceptedPartnerReligions = [.christian]
        state.religion = religion
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            state.lifestyle[question] = CompatibilityScaleAnswer(own: index % 5 + 1, partner: (index * 3) % 5 + 1,
                                                                 isPartnerCustomized: true, importance: index % 5 + 1)
        }
        return state
    }
}
