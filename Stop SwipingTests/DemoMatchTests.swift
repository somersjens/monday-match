import CoreLocation
import XCTest
@testable import Stop_Swiping

@MainActor
final class DemoMatchTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 9)
    private var now: Date {
        BirthDateRules.calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
    }

    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    // MARK: - Scores and requirements

    func testScoresWeighCloseAnswersByImportance() {
        var you = profile(name: "Jens")
        var them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        for question in CompatibilityScaleQuestion.all {
            you.lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 4, isPartnerCustomized: true, importance: 1)
            them.lifestyle[question] = CompatibilityScaleAnswer(own: 4, partner: 1, isPartnerCustomized: true, importance: 5)
        }
        // One question you care about a lot, which they miss by two.
        you.lifestyle[.aloneTime] = CompatibilityScaleAnswer(own: 3, partner: 2, isPartnerCustomized: true, importance: 5)
        let report = MatchReport(you: you, them: them, on: today)
        let questions = Double(CompatibilityScaleQuestion.all.count)
        // "Not important at all" doesn't count, so yours is the one question
        // that matters (weight 8, half right). Habits never count.
        let yours: Double = 50
        XCTAssertEqual(report.yourScore, Int(yours.rounded()))
        // Every answer is two steps from what they want, at weight 8.
        let theirs: Double = (questions * 4) / (questions * 8) * 100
        XCTAssertEqual(report.theirScore, Int(theirs.rounded()))
        let average = Double(report.yourScore + report.theirScore) / 2
        XCTAssertEqual(report.average, Int(average.rounded()))
        XCTAssertEqual(report.rows(.yours).count, CompatibilityScaleQuestion.all.count)
        let alone = report.rows(.yours).first { $0.step == .aloneTime }
        XCTAssertEqual(alone, MatchReport.Row(step: .aloneTime, value: 4, wanted: 2, importance: 5))
        let theirAlone = report.rows(.theirs).first { $0.step == .aloneTime }
        XCTAssertEqual(theirAlone, MatchReport.Row(step: .aloneTime, value: 3, wanted: 1, importance: 5))
    }

    func testRequirementsAreListedTheirsFirstThenYours() {
        var you = profile(name: "Jens")
        you.lifestyle.openToPartnerWithChildren = false
        you.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 1, partnerMaximumLevel: 2)
        you.languages = ["nl"]
        var them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        them.lifestyle.hasChildren = true
        them.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 5, partnerMaximumLevel: 5)
        them.languages = ["en"]
        them.searchRadiusKilometers = 25
        them.location = moved(you.location!, kilometers: 40)
        you.searchRadiusKilometers = 60

        let report = MatchReport(you: you, them: them, on: today)
        XCTAssertFalse(report.isMatch)
        XCTAssertEqual(report.theirIssues, [
            "Emma doesn’t speak Dutch",
            "Emma has kids",
            "Emma drinks alcohol 4+ days a week"
        ])
        XCTAssertEqual(report.yourIssues, [
            "You don’t speak English",
            "You live more than 25 km away from Emma"
        ])
        XCTAssertEqual(report.issues, report.theirIssues + report.yourIssues)

        AppLanguageSettings.shared.language = .dutch
        defer { AppLanguageSettings.shared.language = .english }
        XCTAssertEqual(MatchReport(you: you, them: them, on: today).yourIssues.last,
                       "Je woont meer dan 25 km bij Emma vandaan")
    }

    func testCompatibleProfilesHaveNoIssues() {
        let report = MatchReport(you: profile(name: "Jens"),
                                 them: profile(name: "Emma", gender: .woman, partnerGenders: [.man]), on: today)
        XCTAssertTrue(report.isMatch)
        XCTAssertTrue(report.issues.isEmpty)
    }

    // MARK: - Demo generator

    func testDemoMatchesMeetEveryRequirementAndScoreHigh() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<40 {
            let match = DemoMatchGenerator.makeMatch(for: restrictiveProfile(), shouldMatch: true, now: now, using: &generator)
            let report = match.report
            XCTAssertTrue(report.isMatch, report.issues.joined(separator: "; "))
            XCTAssertFalse(match.name.isEmpty)
            XCTAssertGreaterThanOrEqual(report.yourScore, 70)
            XCTAssertGreaterThanOrEqual(report.theirScore, 70)
        }
    }

    func testDemoNonMatchesFailRequirementsOnBothSides() {
        var generator = SeededGenerator(seed: 11)
        for _ in 0..<40 {
            let report = DemoMatchGenerator.makeMatch(for: restrictiveProfile(), shouldMatch: false, now: now,
                                                      using: &generator).report
            XCTAssertFalse(report.isMatch)
            XCTAssertFalse(report.theirIssues.isEmpty, "Something of theirs doesn't suit you.")
            XCTAssertFalse(report.yourIssues.isEmpty, "Something of yours doesn't suit them.")
        }
    }

    func testDemoNonMatchHasReasonsEvenForAnOpenProfile() {
        var you = profile(name: "Jens")
        you.partnerAgeRange = PartnerAgeRange(minimum: 18, maximum: 99, isCustomized: true)
        var generator = SeededGenerator(seed: 3)
        for _ in 0..<20 {
            XCTAssertFalse(DemoMatchGenerator.makeMatch(for: you, shouldMatch: false, now: now, using: &generator).report.isMatch)
        }
    }

    func testTheExampleIsAnEightyPercentMatch() {
        var generator = SeededGenerator(seed: 11)
        for you in [profile(name: "Jens"), restrictiveProfile()] {
            for _ in 0..<25 {
                let match = DemoMatchGenerator.makeExample(for: you, now: now, using: &generator)
                let report = match.report
                XCTAssertEqual(match.name, "Example")
                XCTAssertTrue(report.isMatch, report.issues.joined(separator: "; "))
                XCTAssertEqual(report.average, 80, "\(report.yourScore) and \(report.theirScore)")
                XCTAssertLessThanOrEqual(abs(report.yourScore - report.theirScore), 12)
            }
        }
    }

    // MARK: - Saved matches

    func testSavedMatchesAreSnapshotsKeptNewestFirst() throws {
        let suite = "DemoMatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var generator = SeededGenerator(seed: 5)
        var you = restrictiveProfile()
        let older = DemoMatchGenerator.makeMatch(for: you, shouldMatch: true, now: now, using: &generator)
        let newer = DemoMatchGenerator.makeMatch(for: you, shouldMatch: false, now: now.addingTimeInterval(60), using: &generator)
        let score = older.report.average

        let store = SavedMatchStore(defaults: defaults)
        store.save(older)
        store.save(newer)
        store.save(older)
        XCTAssertEqual(store.matches.map(\.id), [newer.id, older.id])

        // Changing your profile afterwards leaves the saved scores alone.
        for question in CompatibilityScaleQuestion.all {
            you.lifestyle[question] = CompatibilityScaleAnswer(own: 1, partner: 1, isPartnerCustomized: true, importance: 5)
        }
        let reloaded = SavedMatchStore(defaults: defaults)
        XCTAssertEqual(reloaded.matches, [newer, older])
        XCTAssertEqual(reloaded.matches.last?.report.average, score)

        reloaded.delete(newer.id)
        XCTAssertEqual(SavedMatchStore(defaults: defaults).matches.map(\.id), [older.id])
        XCTAssertFalse(reloaded.contains(newer.id))
    }

    // MARK: - Name

    func testRenamingSavedMatchPersistsWithoutChangingProfilesScoresOrOrder() throws {
        let suite = "DemoMatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var generator = SeededGenerator(seed: 5)
        let original = DemoMatchGenerator.makeMatch(for: restrictiveProfile(), shouldMatch: false, now: now, using: &generator)
        let newer = DemoMatchGenerator.makeMatch(for: restrictiveProfile(), shouldMatch: true, now: now.addingTimeInterval(60), using: &generator)
        let store = SavedMatchStore(defaults: defaults)
        store.save(original)
        store.save(newer)
        store.rename(original.id, to: "  Alex   Robin  ")
        store.rename(original.id, to: " \n ")

        let reloaded = SavedMatchStore(defaults: defaults)
        XCTAssertEqual(reloaded.matches.map(\.id), [newer.id, original.id])
        let renamed = try XCTUnwrap(reloaded.matches.last)
        XCTAssertEqual(renamed.name, "Alex Robin")
        XCTAssertEqual(renamed.you, original.you)
        XCTAssertEqual(renamed.them, original.them)
        XCTAssertEqual(renamed.matchedAt, original.matchedAt)
        XCTAssertEqual(renamed.report.yourScore, original.report.yourScore)
        XCTAssertEqual(renamed.report.theirScore, original.report.theirScore)
        XCTAssertEqual(renamed.report.isMatch, original.report.isMatch)
        XCTAssertTrue(renamed.report.issues.contains { $0.contains("Alex Robin") })
        XCTAssertFalse(renamed.report.issues.contains { $0.contains(original.name) })

        store.rename(original.id, to: original.name)
        XCTAssertNil(SavedMatchStore(defaults: defaults).matches.last?.customName)
    }

    func testUnsavedMatchCanBeRenamedAndOlderSnapshotsStillDecode() throws {
        var generator = SeededGenerator(seed: 9)
        var match = DemoMatchGenerator.makeMatch(for: restrictiveProfile(), shouldMatch: true, now: now, using: &generator)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as? [String: Any])
        json.removeValue(forKey: "customName")
        let legacy = try JSONDecoder().decode(MatchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy, match)
        XCTAssertEqual(legacy.name, match.them.displayName)
        XCTAssertFalse(match.rename(to: "  "))
        XCTAssertTrue(match.rename(to: String(repeating: "a", count: 50)))
        XCTAssertEqual(match.name.count, ProfileNameRules.maximumLength)
        XCTAssertEqual(try JSONDecoder().decode(MatchSnapshot.self, from: JSONEncoder().encode(match)), match)
    }

    func testNameIsTrimmedSavedAndNeverCleared() {
        let store = InMemoryProfileCreationStore(state: profile(name: ""))
        let repository = InMemoryProfileRepository()
        let viewModel = ProfileCreationViewModel(store: store, repository: repository, now: { self.now })
        XCTAssertFalse(viewModel.hasDisplayName)

        XCTAssertFalse(viewModel.setDisplayName("   "))
        XCTAssertTrue(viewModel.setDisplayName("  Jens   Peter "))
        XCTAssertEqual(viewModel.state.displayName, "Jens Peter")
        XCTAssertEqual(store.state?.displayName, "Jens Peter")
        XCTAssertFalse(viewModel.setDisplayName(""))
        XCTAssertEqual(viewModel.state.displayName, "Jens Peter")
        XCTAssertTrue(viewModel.setDisplayName(String(repeating: "a", count: 50)))
        XCTAssertEqual(viewModel.state.displayName.count, ProfileNameRules.maximumLength)
    }

    func testStatesSavedBeforeNamesStillDecode() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile(name: "Jens"))) as? [String: Any])
        json.removeValue(forKey: "storedDisplayName")
        let state = try JSONDecoder().decode(ProfileCreationState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(state.displayName, "")
    }

    // MARK: - Animation timeline

    func testMatchTimelineLeavesThenDrawsTheHeart() {
        let start = WelcomeLightMatch.pose(elapsed: 0, isMatch: true)
        XCTAssertEqual(start.exit, 0)
        XCTAssertEqual(start.head, 0)
        let gone = WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.exitDuration, isMatch: true)
        XCTAssertEqual(gone.exit, 1)
        XCTAssertEqual(gone.head, 0, accuracy: 1e-9)

        var previous = gone
        for step in 1...100 {
            let pose = WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.exitDuration + Double(step) * 0.03, isMatch: true)
            XCTAssertGreaterThanOrEqual(pose.head, previous.head)
            XCTAssertGreaterThanOrEqual(pose.tail, previous.tail)
            XCTAssertLessThanOrEqual(pose.tail, WelcomeLightMatch.cuspS + 1e-9, "The heart itself is never pulled away.")
            XCTAssertEqual(pose.breakAmount, 0)
            previous = pose
        }
        let done = WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.heartEnd, isMatch: true)
        XCTAssertGreaterThan(done.head, 1)
        XCTAssertEqual(done.tail, WelcomeLightMatch.cuspS, accuracy: 1e-9)

        XCTAssertEqual(WelcomeLightMatch.head(at: WelcomeLightMatch.averageRevealTime), WelcomeLightMatch.tipS, accuracy: 1e-6)
        XCTAssertLessThan(WelcomeLightMatch.averageRevealTime, WelcomeLightMatch.scoresRevealTime)
        XCTAssertLessThanOrEqual(WelcomeLightMatch.scoresRevealTime, WelcomeLightMatch.controlsRevealTime(isMatch: true))
    }

    func testNoMatchHeartBreaksOnlyOnceComplete() {
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.heartEnd, isMatch: false).breakAmount, 0)
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: WelcomeLightMatch.breakStart + WelcomeLightMatch.breakDuration,
                                              isMatch: false).breakAmount, 1)
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: 99, isMatch: true).breakAmount, 0)
        XCTAssertLessThan(WelcomeLightMatch.Layout.noMatch.lineY, WelcomeLightMatch.Layout.match.lineY,
                          "Without a match the line sits higher, leaving room for the reasons.")
        XCTAssertGreaterThan(WelcomeLightMatch.controlsRevealTime(isMatch: false), WelcomeLightMatch.issuesRevealTime)
    }

    func testReduceMotionShowsTheFinishedHeart() {
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: 0, isMatch: true, reduceMotion: true),
                       .init(exit: 1, head: 1.04, tail: WelcomeLightMatch.cuspS, breakAmount: 0))
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: 0, isMatch: false, reduceMotion: true).breakAmount, 1)
    }

    func testSavedMatchMorphsImmediatelyAndRevealsOnItsShorterTimeline() throws {
        let transition = WelcomeLightMatch.Transition.savedMatch
        let start = WelcomeLightMatch.pose(elapsed: 0, isMatch: true, transition: transition)
        XCTAssertEqual(start.exit, 0)
        XCTAssertEqual(start.morph, 0)
        let moving = WelcomeLightMatch.pose(elapsed: 0.2, isMatch: true, transition: transition)
        XCTAssertEqual(moving.exit, 0, "Saved matches must never send the helix above the heart.")
        XCTAssertGreaterThan(try XCTUnwrap(moving.morph), 0)
        XCTAssertEqual(start.head, WelcomeLightMatch.cuspS)
        XCTAssertGreaterThan(moving.head, WelcomeLightMatch.cuspS, "The strands feed straight into the lobes from the cusp.")

        let end = transition.time(WelcomeLightMatch.heartEnd)
        XCTAssertEqual(end, 2.2, accuracy: 1e-9)
        let done = WelcomeLightMatch.pose(elapsed: end, isMatch: true, transition: transition)
        XCTAssertEqual(done.morph, 1)
        XCTAssertEqual(done.head, 1.04, accuracy: 1e-9)
        XCTAssertEqual(done.tail, WelcomeLightMatch.cuspS, accuracy: 1e-9)
        for (time, head) in [(WelcomeLightMatch.averageRevealTime, WelcomeLightMatch.tipS),
                             (WelcomeLightMatch.scoresRevealTime, 0.96)] {
            let pose = WelcomeLightMatch.pose(elapsed: transition.time(time), isMatch: true, transition: transition)
            XCTAssertEqual(pose.head, head, accuracy: 1e-9)
        }
        let breakStart = transition.time(WelcomeLightMatch.breakStart)
        XCTAssertGreaterThan(breakStart, end)
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: breakStart, isMatch: false, transition: transition).breakAmount, 0)
        XCTAssertEqual(WelcomeLightMatch.pose(elapsed: breakStart + WelcomeLightMatch.breakDuration,
                                            isMatch: false, transition: transition).breakAmount, 1)
        let reduced = WelcomeLightMatch.pose(elapsed: 0, isMatch: false, reduceMotion: true, transition: transition)
        XCTAssertEqual(reduced.morph, 1)
        XCTAssertEqual(reduced.breakAmount, 1)
    }

    func testSavedMatchSharesASlowVerticalDriftWithoutAnInitialDrop() {
        for layout in [WelcomeLightMatch.Layout.match, .noMatch] {
            let start = WelcomeLightMatch.sharedOffset(progress: 0, layout: layout)
            let cuspY = -0.62 * layout.scale + layout.offsetY
            XCTAssertEqual(cuspY + start, -WelcomeLightHelix.halfHeight, accuracy: 1e-9,
                "The heart must start at the existing helix tip.")
            let earlyDrift = WelcomeLightMatch.sharedOffset(progress: 0.1, layout: layout) - start
            XCTAssertGreaterThan(earlyDrift, 0)
            XCTAssertLessThan(earlyDrift, 0.005, "The first 0.22 seconds must not contain a visible downward step.")
            var previous = start
            for i in 1...100 {
                let offset = WelcomeLightMatch.sharedOffset(progress: Double(i) / 100, layout: layout)
                XCTAssertGreaterThanOrEqual(offset, previous - 1e-12)
                XCTAssertLessThan(offset - previous, 0.008, "The shared motion must be distributed smoothly over the morph.")
                previous = offset
            }
            XCTAssertEqual(previous, 0, accuracy: 1e-9)
        }
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

    /// Many requirements, so the generator has to respect all of them.
    private func restrictiveProfile() -> ProfileCreationState {
        var state = profile(name: "Jens")
        state.partnerAgeRange = PartnerAgeRange(minimum: 26, maximum: 34, isCustomized: true)
        state.partnerHeightRange = PartnerHeightRange(minimum: 160, maximum: 180)
        state.lifestyle.hasChildren = true
        state.lifestyle.openToPartnerWithChildren = false
        state.lifestyle.futureChildren = .yes
        state.lifestyle[.alcohol] = SubstanceAnswer(ownLevel: 3, partnerMaximumLevel: 2)
        state.lifestyle[.smoking] = SubstanceAnswer(ownLevel: 0, partnerMaximumLevel: 0)
        var religion = ReligionAnswers()
        religion.own = .christian
        religion.acceptedPartnerReligions = [.christian, .none, .spiritual]
        state.religion = religion
        state.searchRadiusKilometers = 20
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            state.lifestyle[question] = CompatibilityScaleAnswer(own: index % 5 + 1, partner: (index * 3) % 5 + 1,
                                                                 isPartnerCustomized: true, importance: index % 5 + 1)
        }
        return state
    }

    private func moved(_ location: SelectedLocation, kilometers: Double) -> SelectedLocation {
        SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: location.latitude + kilometers / 111.2,
                                                            longitude: location.longitude), source: .map)
    }
}

/// SplitMix64, so generated demo profiles are repeatable in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
