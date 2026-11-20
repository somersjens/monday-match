import CoreLocation
import XCTest
@testable import Stop_Swiping

/// What a match keeps about the other person: scores per category that add
/// up to the totals, worked out once, and never a single answer.
@MainActor
final class MatchPrivacyTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 13)
    private var now: Date {
        BirthDateRules.calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 15))!
    }

    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    // MARK: - Categories

    func testCategoriesAddUpToEachScore() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<40 {
            let you = randomProfile(name: "Jens", using: &generator)
            let them = randomProfile(name: "Emma", gender: .woman, partnerGenders: [.man], using: &generator)
            let report = MatchReport(you: you, them: them, on: today)
            for perspective in [MatchReport.Perspective.yours, .theirs] {
                let categories = report.categories(perspective)
                XCTAssertEqual(categories.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
                let total = categories.reduce(0) { $0 + $1.share * ($1.fit ?? 0) } * 100
                XCTAssertEqual(Int(total.rounded()), report.score(perspective), "\(perspective)")
            }
            // Both ways at once: the average of the two scores.
            let together = report.result.together
            XCTAssertEqual(together.reduce(0) { $0 + $1.share }, 1, accuracy: 1e-9)
            let total = together.reduce(0) { $0 + $1.share * ($1.fit ?? 0) } * 100
            XCTAssertEqual(total, Double(report.yourScore + report.theirScore) / 2, accuracy: 0.5)
        }
    }

    func testEveryQuestionCountsByItsOwnImportance() throws {
        var you = profile(name: "Jens")
        let them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        for question in CompatibilityScaleQuestion.all { you.lifestyle[question].importance = 1 }
        // Emma answers 3 everywhere. You want a 1 where it matters a lot to
        // you (importance 5, weight 8, two steps off: half a fit) and a 3
        // where it matters a little (importance 2, weight 1, a full fit).
        let alone = try XCTUnwrap(CompatibilityScaleQuestion.question(for: .aloneTime))
        let pets = try XCTUnwrap(CompatibilityScaleQuestion.question(for: .pets))
        you.lifestyle[alone] = CompatibilityScaleAnswer(own: 3, partner: 1, isPartnerCustomized: true, importance: 5)
        you.lifestyle[pets] = CompatibilityScaleAnswer(own: 3, partner: 3, isPartnerCustomized: true, importance: 2)
        let report = MatchReport(you: you, them: them, on: today)
        // (8 × 0.5 + 1 × 1) ÷ 9, not the plain average of the two questions.
        XCTAssertEqual(report.yourScore, Int((5.0 / 9 * 100).rounded()))
        let closeness = report.categories(.yours).first { $0.category == .closeness }
        XCTAssertEqual(try XCTUnwrap(closeness?.fit), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(closeness?.share), 8.0 / 9, accuracy: 1e-12)
    }

    func testEachDirectionUsesOnlyTheSeekersOwnImportance() {
        var generator = SeededGenerator(seed: 11)
        let you = randomProfile(name: "Jens", using: &generator)
        let them = randomProfile(name: "Emma", gender: .woman, partnerGenders: [.man], using: &generator)
        let base = MatchReport(you: you, them: them, on: today)

        // Emma changes how much each question matters to her: only her score of you moves.
        var reweighedThem = them
        for question in CompatibilityScaleQuestion.all {
            reweighedThem.lifestyle[question].importance = Int.random(in: 1...5, using: &generator)
        }
        let afterThem = MatchReport(you: you, them: reweighedThem, on: today)
        XCTAssertEqual(afterThem.yourScore, base.yourScore)
        XCTAssertEqual(afterThem.categories(.yours), base.categories(.yours))
        XCTAssertNotEqual(afterThem.categories(.theirs), base.categories(.theirs))

        // You change yours: only your score of her moves.
        var reweighedYou = you
        for question in CompatibilityScaleQuestion.all {
            reweighedYou.lifestyle[question].importance = Int.random(in: 1...5, using: &generator)
        }
        let afterYou = MatchReport(you: reweighedYou, them: them, on: today)
        XCTAssertEqual(afterYou.theirScore, base.theirScore)
        XCTAssertEqual(afterYou.categories(.theirs), base.categories(.theirs))
        XCTAssertNotEqual(afterYou.categories(.yours), base.categories(.yours))
    }

    func testEveryCategoryAppearsInCatalogOrder() {
        let report = MatchReport(you: profile(name: "Jens"), them: profile(name: "Emma", gender: .woman, partnerGenders: [.man]),
                                 on: today)
        XCTAssertEqual(report.categories(.yours).map(\.category), CompatibilityCategory.allCases)
        XCTAssertEqual(CompatibilityScaleQuestion.sections.map(\.category), CompatibilityCategory.allCases)
        for question in CompatibilityScaleQuestion.all {
            XCTAssertNotNil(CompatibilityScaleQuestion.category(for: question.step), question.id)
        }
    }

    func testACategoryThatDoesNotMatterCountsForNothing() {
        var you = profile(name: "Jens")
        let them = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        let homeLife = CompatibilityScaleQuestion.sections.first { $0.category == .homeLife }!.questions
        for question in homeLife { you.lifestyle[question].importance = 1 }
        let fit = MatchReport(you: you, them: them, on: today).categories(.yours).first { $0.category == .homeLife }
        XCTAssertNil(fit?.fit)
        XCTAssertEqual(fit?.share, 0)
    }

    func testNothingMatteringScoresFullAndCountsCategoriesByTheirQuestions() {
        var you = profile(name: "Jens")
        for question in CompatibilityScaleQuestion.all { you.lifestyle[question].importance = 1 }
        let report = MatchReport(you: you, them: profile(name: "Emma", gender: .woman, partnerGenders: [.man]), on: today)
        XCTAssertEqual(report.yourScore, 100)
        let questions = Double(CompatibilityScaleQuestion.all.count)
        for fit in report.categories(.yours) {
            XCTAssertEqual(fit.fit, 1)
            let count = CompatibilityScaleQuestion.sections.first { $0.category == fit.category }!.questions.count
            XCTAssertEqual(fit.share, Double(count) / questions, accuracy: 1e-12)
        }
    }

    // MARK: - What a match keeps

    func testAMatchKeepsNoSingleAnswerOfTheOtherPerson() throws {
        let you = profile(name: "Jens")
        var generator = SeededGenerator(seed: 42)
        let them = randomProfile(name: "Emma", gender: .woman, partnerGenders: [.man], using: &generator)
        let snapshot = MatchSnapshot(matchedAt: now, you: you, them: them)
        for question in CompatibilityScaleQuestion.all {
            XCTAssertEqual(snapshot.them.lifestyle[question], CompatibilityScaleAnswer(), question.id)
        }
        XCTAssertNil(snapshot.them.partnerAgeRange)
        XCTAssertEqual(snapshot.them.partnerHeightRange, .any)
        XCTAssertEqual(snapshot.them.searchRadiusKilometers, SearchRadiusRules.defaultKilometers)
        // What the screens show stays.
        XCTAssertEqual(snapshot.them.displayName, "Emma")
        XCTAssertEqual(snapshot.them.age(on: today), them.age(on: today))
        XCTAssertEqual(snapshot.them.lifestyle[.alcohol], them.lifestyle[.alcohol])
        XCTAssertEqual(snapshot.them.religion, them.religion)
        XCTAssertTrue(snapshot.sharedFacts.contains { $0.value == "Gent" })
        // And the outcome is the same as comparing the whole profiles.
        XCTAssertEqual(snapshot.report, MatchReport(you: you, them: them, on: today, name: "Emma"))
    }

    func testAKeptMatchNeverChangesAfterwards() throws {
        let you = profile(name: "Jens")
        var generator = SeededGenerator(seed: 42)
        let them = randomProfile(name: "Emma", gender: .woman, partnerGenders: [.man], using: &generator)
        let snapshot = MatchSnapshot(matchedAt: now, you: you, them: them)
        let reloaded = try JSONDecoder().decode(MatchSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(reloaded, snapshot)
        XCTAssertEqual(reloaded.report, snapshot.report)
        // Replaying it as a demo keeps the outcome.
        XCTAssertEqual(snapshot.replayedAsDemo().result, snapshot.result)
        XCTAssertNotEqual(snapshot.replayedAsDemo().id, snapshot.id)
    }

    func testALiveMatchIsWorkedOutOnceFromTheCards() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPrivacyTests-\(UUID())"))
        let mila = profile(name: "Mila", gender: .woman, partnerGenders: [.man])
        let card = try XCTUnwrap(ProfileCode.card(for: mila.sharedCopy(today: .today())))
        let match = CloudChatMatch(id: UUID(), partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                   matchedAt: now, partnerCard: card)
        let center = LiveMatchCenter(repository: nil, defaults: defaults)
        var before = profile(name: "Jens")
        for question in CompatibilityScaleQuestion.all { before.lifestyle[question].partner = 5 }
        let first = center.snapshot(of: match, fallbackYou: before)
        XCTAssertEqual(first.report.yourScore, 80)
        XCTAssertFalse(first.report.categories(.yours).isEmpty)

        // Whatever this profile becomes later, the match stays as it was.
        var after = before
        for question in CompatibilityScaleQuestion.all { after.lifestyle[question].partner = 1 }
        let second = center.snapshot(of: match, fallbackYou: after)
        XCTAssertEqual(second.result, first.result)
    }

    // MARK: - Scanning the same person again

    func testScanningTheSamePersonAgainShowsTheFirstOutcome() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPrivacyTests-\(UUID())"))
        let memory = ScannedMatchMemory(defaults: defaults)
        let holder = ProfileHolder(bytes: Data([4, 4, 4, 4, 4, 4, 4, 4]))
        let emma = profile(name: "Emma", gender: .woman, partnerGenders: [.man])
        var you = profile(name: "Jens")
        let first = memory.resolve(MatchSnapshot(matchedAt: now, you: you, them: emma), for: holder, now: now)

        // You change your answers and scan Emma's fresh code an hour later.
        for question in CompatibilityScaleQuestion.all { you.lifestyle[question].own = 5 }
        let later = now.addingTimeInterval(3600)
        let again = memory.resolve(MatchSnapshot(matchedAt: later, you: you, them: emma), for: holder, now: later)
        XCTAssertEqual(again, first, "Trying other answers on the same person reveals nothing.")

        // Someone else is compared afresh.
        let other = ProfileHolder(bytes: Data([5, 5, 5, 5, 5, 5, 5, 5]))
        let noor = memory.resolve(MatchSnapshot(matchedAt: later, you: you, them: emma), for: other, now: later)
        XCTAssertNotEqual(noor.id, first.id)

        // After a day the person is compared again.
        let nextDay = now.addingTimeInterval(ScannedMatchMemory.lifetime + 1)
        let fresh = memory.resolve(MatchSnapshot(matchedAt: nextDay, you: you, them: emma), for: holder, now: nextDay)
        XCTAssertNotEqual(fresh.id, first.id)

        // The memory holds outcomes, never the other person's answers.
        let kept = try XCTUnwrap(memory.snapshot(for: holder, now: nextDay))
        for question in CompatibilityScaleQuestion.all {
            XCTAssertEqual(kept.them.lifestyle[question], CompatibilityScaleAnswer(), question.id)
        }
        ScannedMatchMemory.clear(defaults: defaults)
        XCTAssertNil(memory.snapshot(for: holder, now: nextDay))
    }

    func testEachPhoneKeepsOneHolderUntilTheProfileIsDeleted() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPrivacyTests-\(UUID())"))
        let first = ProfileHolder.current(defaults: defaults)
        XCTAssertEqual(ProfileHolder.current(defaults: defaults), first)
        XCTAssertEqual(first.bytes.count, ProfileHolder.byteCount)
        ProfileHolder.clear(defaults: defaults)
        XCTAssertNotEqual(ProfileHolder.current(defaults: defaults), first)
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
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72),
                                          source: .map, placeName: "Gent")
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

    private func randomProfile<R: RandomNumberGenerator>(name: String, gender: GenderIdentity = .man,
                                                         partnerGenders: Set<GenderIdentity> = [.woman],
                                                         using generator: inout R) -> ProfileCreationState {
        var state = profile(name: name, gender: gender, partnerGenders: partnerGenders)
        for question in CompatibilityScaleQuestion.all {
            state.lifestyle[question] = CompatibilityScaleAnswer(
                own: Int.random(in: 1...5, using: &generator), partner: Int.random(in: 1...5, using: &generator),
                isPartnerCustomized: true, importance: Int.random(in: 1...5, using: &generator))
        }
        return state
    }
}
