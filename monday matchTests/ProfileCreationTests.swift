import CoreLocation
import XCTest
import UIKit
@testable import monday_match

@MainActor
final class ProfileCreationRulesTests: XCTestCase {
    private let today = CalendarDate(year: 2026, month: 11, day: 9)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        return calendar
    }

    func testAgeCountsCompletedYearsOnTheLocalCalendar() {
        XCTAssertEqual(BirthDateRules.age(of: .init(year: 2000, month: 11, day: 9), on: today), 26)
        XCTAssertEqual(BirthDateRules.age(of: .init(year: 2000, month: 11, day: 10), on: today), 25)
        XCTAssertEqual(BirthDateRules.age(of: .init(year: 2008, month: 11, day: 9), on: today), 18)
        XCTAssertEqual(BirthDateRules.age(of: .init(year: 2008, month: 11, day: 10), on: today), 17)
    }

    func testLeapDayBirthdaysTurnOverOnFirstMarchInCommonYears() {
        let leapling = CalendarDate(year: 2008, month: 2, day: 29)
        XCTAssertEqual(BirthDateRules.age(of: leapling, on: .init(year: 2026, month: 2, day: 28)), 17)
        XCTAssertEqual(BirthDateRules.age(of: leapling, on: .init(year: 2026, month: 3, day: 1)), 18)
        XCTAssertEqual(BirthDateRules.age(of: leapling, on: .init(year: 2028, month: 2, day: 29)), 20)
    }

    func testEvaluationRejectsTodayNonexistentFutureAndMinorDates() {
        XCTAssertEqual(BirthDateRules.evaluate(today, today: today, calendar: calendar), .today)
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 2001, month: 2, day: 29), today: today, calendar: calendar),
                       .nonexistent(daysInMonth: 28))
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 2000, month: 2, day: 29), today: today, calendar: calendar),
                       .adult(age: 26))
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 1990, month: 4, day: 31), today: today, calendar: calendar),
                       .nonexistent(daysInMonth: 30))
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 2026, month: 11, day: 10), today: today, calendar: calendar), .future)
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 2030, month: 1, day: 1), today: today, calendar: calendar), .future)
        XCTAssertEqual(BirthDateRules.evaluate(.init(year: 2010, month: 5, day: 5), today: today, calendar: calendar), .minor(age: 16))
    }

    func testPartnerAgeDefaultsFollowTheUsersAgeWithAnAdultFloor() {
        XCTAssertEqual(PartnerAgeRules.suggestedRange(forAge: 24), PartnerAgeRange(minimum: 19, maximum: 29))
        XCTAssertEqual(PartnerAgeRules.suggestedRange(forAge: 20), PartnerAgeRange(minimum: 18, maximum: 25))
        XCTAssertEqual(PartnerAgeRules.suggestedRange(forAge: 18), PartnerAgeRange(minimum: 18, maximum: 23))
        XCTAssertEqual(PartnerAgeRules.suggestedRange(forAge: 97), PartnerAgeRange(minimum: 92, maximum: 99))
    }

    func testPartnerAgeRangeCannotCrossOrLeaveItsBounds() {
        XCTAssertTrue(PartnerAgeRules.clamped(minimum: 40, maximum: 30) == (40, 40))
        XCTAssertTrue(PartnerAgeRules.clamped(minimum: 12, maximum: 150) == (18, 99))
    }

    func testHeightAndRadiusAreClamped() {
        XCTAssertEqual(HeightRules.clamped(80), 100)
        XCTAssertEqual(HeightRules.clamped(300), 240)
        XCTAssertEqual(HeightRules.imperialDescription(centimeters: 175), "5′ 9″")
        XCTAssertEqual(SearchRadiusRules.clamped(0), 1)
        XCTAssertEqual(SearchRadiusRules.clamped(500), 200)
    }

    func testSingleSelectPreferenceReplacesItsAnswer() {
        var answers = RelationshipPreferenceAnswers()
        let question = RelationshipPreferenceQuestion.sexualArrangement
        XCTAssertFalse(answers.isAnswered(question))
        answers.select("partnerOnly", in: question)
        answers.select("noSex", in: question)
        XCTAssertEqual(answers.selectedOptionIDs(for: question), ["noSex"])
        XCTAssertTrue(answers.isAnswered(question))
    }

    func testLanguageCatalogHasUniqueNamedEntries() {
        let codes = LanguageCatalog.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertGreaterThan(codes.count, 100)
        XCTAssertTrue(codes.contains("en"))
        XCTAssertTrue(codes.contains("nl"))
    }

    func testOlderDraftsWithoutProfileCreationFieldsStillDecode() throws {
        let encoded = try JSONEncoder().encode(ProfileDraft())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["heightCentimeters", "preferredPartnerMinimumAge", "preferredPartnerMaximumAge",
                    "relationshipPreferences", "languages", "profileCreationCompletedAt"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let draft = try JSONDecoder().decode(ProfileDraft.self, from: legacy)
        XCTAssertEqual(draft.languages, [])
        XCTAssertFalse(draft.hasCompletedProfileCreation)
    }
}

@MainActor
final class ProfileCreationViewModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15))!
    }

    private let today = CalendarDate(year: 2026, month: 11, day: 9)

    private func makeViewModel(
        store: InMemoryProfileCreationStore? = nil,
        repository: InMemoryProfileRepository? = nil
    ) -> ProfileCreationViewModel {
        let now = now
        return ProfileCreationViewModel(
            store: store ?? InMemoryProfileCreationStore(),
            repository: repository ?? InMemoryProfileRepository(),
            calendar: calendar,
            now: { now }
        )
    }

    func testBirthdayStartsOnTodayAndCannotBeSubmittedUnchanged() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.birthDateSelection, today)
        XCTAssertNil(viewModel.visibleAge, "The age stays hidden until a field changes.")
        XCTAssertTrue(viewModel.canContinue)

        XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)
        XCTAssertEqual(viewModel.feedback, .birthday)
        XCTAssertEqual(viewModel.feedback?.message, "Go celebrate your birthday, come back tomorrow.")
        XCTAssertEqual(viewModel.currentStep, .dateOfBirth)
        XCTAssertEqual(viewModel.rejectionCount, 1)
    }

    func testAgeAppearsAfterOneFieldChanges() {
        let viewModel = makeViewModel()
        viewModel.updateBirthDate(.init(year: 2000, month: 11, day: 9))
        XCTAssertEqual(viewModel.visibleAge, 26)
        XCTAssertFalse(viewModel.shouldAutoAdvanceFromBirthDate, "Only one field changed.")
    }

    func testAutoAdvanceNeedsAllThreeFieldsAndOnlyFiresOncePerSelection() {
        let viewModel = makeViewModel()
        viewModel.updateBirthDate(.init(year: 2000, month: 3, day: 9))
        XCTAssertFalse(viewModel.shouldAutoAdvanceFromBirthDate)
        viewModel.updateBirthDate(.init(year: 2000, month: 3, day: 14))
        XCTAssertTrue(viewModel.shouldAutoAdvanceFromBirthDate)

        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .partnerAgeRange)
        XCTAssertEqual(viewModel.partnerAgeRange, PartnerAgeRange(minimum: 21, maximum: 31))

        XCTAssertTrue(viewModel.goBack())
        XCTAssertEqual(viewModel.birthDateSelection, .init(year: 2000, month: 3, day: 14), "Back keeps the birthday.")
        XCTAssertFalse(viewModel.shouldAutoAdvanceFromBirthDate, "An accepted selection must not advance again.")
    }

    func testImpossibleAndFutureDatesNeverAdvance() {
        let viewModel = makeViewModel()
        viewModel.updateBirthDate(.init(year: 2001, month: 2, day: 29))
        XCTAssertFalse(viewModel.shouldAutoAdvanceFromBirthDate)
        XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)
        if case .nonexistentDate(_, 2001, 28)? = viewModel.feedback {} else {
            XCTFail("Expected a nonexistent date message, got \(String(describing: viewModel.feedback))")
        }

        viewModel.updateBirthDate(.init(year: 2026, month: 12, day: 1))
        XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)
        XCTAssertEqual(viewModel.feedback, .futureDate)
        XCTAssertEqual(viewModel.currentStep, .dateOfBirth)
    }

    func testMinorIsLockedAndAnswersAreDiscarded() {
        let store = InMemoryProfileCreationStore()
        let viewModel = makeViewModel(store: store)
        viewModel.updateBirthDate(.init(year: 2010, month: 6, day: 1))
        XCTAssertEqual(viewModel.submitCurrentStep(), .underage)
        XCTAssertTrue(viewModel.isUnderageLocked)
        XCTAssertNil(viewModel.state.dateOfBirth)
        XCTAssertEqual(store.state?.isUnderageLocked, true, "The lock survives relaunch.")

        let relaunched = makeViewModel(store: store)
        XCTAssertTrue(relaunched.isUnderageLocked)
        XCTAssertEqual(relaunched.currentStep, .dateOfBirth)
    }

    func testRestartingAfterTheLockOnlyReopensValidation() {
        let viewModel = makeViewModel()
        viewModel.updateBirthDate(.init(year: 2012, month: 1, day: 1))
        XCTAssertEqual(viewModel.submitCurrentStep(), .underage)

        viewModel.restartAfterUnderageLock()
        XCTAssertFalse(viewModel.isUnderageLocked)
        XCTAssertEqual(viewModel.birthDateSelection, today)
        XCTAssertNil(viewModel.visibleAge)
        XCTAssertFalse(viewModel.isComplete(.dateOfBirth), "Restarting grants nothing.")

        viewModel.updateBirthDate(.init(year: 2012, month: 1, day: 1))
        XCTAssertEqual(viewModel.submitCurrentStep(), .underage, "The same minor date is rejected again.")
    }

    func testBackPreservesAnswersAndContinueRequiresInput() {
        let viewModel = makeViewModel()
        advancePastBirthday(viewModel)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced) // accepted age range default

        viewModel.updateHeight(182)
        XCTAssertTrue(viewModel.state.hasAdjustedHeight)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .partnerHeightRange)
        XCTAssertTrue(viewModel.canContinue, "Any height is a valid answer.")
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)

        XCTAssertFalse(viewModel.canContinue, "Gender has no preselection.")
        XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)
        viewModel.selectGender(.woman)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)

        viewModel.togglePartnerGender(.man)
        viewModel.togglePartnerGender(.nonBinary)
        viewModel.togglePartnerGender(.man)
        XCTAssertEqual(viewModel.state.partnerGenders, [.nonBinary])
        viewModel.togglePartnerGender(.nonBinary)
        XCTAssertFalse(viewModel.canContinue, "At least one partner gender is required.")
        viewModel.togglePartnerGender(.man)

        XCTAssertTrue(viewModel.goBack())
        XCTAssertTrue(viewModel.goBack())
        XCTAssertTrue(viewModel.goBack())
        XCTAssertEqual(viewModel.currentStep, .height)
        XCTAssertEqual(viewModel.state.heightCentimeters, 182)
        XCTAssertEqual(viewModel.state.gender, .woman)
        XCTAssertEqual(viewModel.state.partnerGenders, [.man])
    }

    func testLanguagesKeepAtLeastOneAndRejectDuplicates() {
        let viewModel = makeViewModel()
        let initial = viewModel.state.languages
        XCTAssertEqual(initial.count, 1, "The app language is preselected.")

        viewModel.addLanguage("fr")
        viewModel.addLanguage("fr")
        XCTAssertEqual(viewModel.state.languages, initial + ["fr"])

        viewModel.replaceLanguage("fr", with: initial[0])
        XCTAssertEqual(viewModel.state.languages, initial + ["fr"], "Replacing with a selected language is ignored.")
        viewModel.replaceLanguage(initial[0], with: "de")
        XCTAssertEqual(viewModel.state.languages, ["de", "fr"])

        viewModel.removeLanguage("de")
        viewModel.removeLanguage("fr")
        XCTAssertEqual(viewModel.state.languages, ["fr"])
    }

    func testCompletionWritesTheProfileDraft() throws {
        let repository = InMemoryProfileRepository()
        let viewModel = makeViewModel(repository: repository)
        advancePastBirthday(viewModel)
        viewModel.updatePartnerAgeRange(minimum: 25, maximum: 40)
        viewModel.submitCurrentStep()
        viewModel.submitCurrentStep() // default height
        viewModel.updatePartnerHeightRange(minimum: 165, maximum: 190)
        viewModel.submitCurrentStep()
        viewModel.selectGender(.man)
        viewModel.submitCurrentStep()
        viewModel.togglePartnerGender(.woman)
        viewModel.submitCurrentStep()
        XCTAssertFalse(viewModel.canContinue)
        viewModel.selectPreference("partnerOnly", in: .sexualArrangement)
        viewModel.submitCurrentStep()
        viewModel.addLanguage("es")
        viewModel.submitCurrentStep()

        XCTAssertEqual(viewModel.currentStep, .location)
        XCTAssertFalse(viewModel.canContinue, "A location is required.")
        viewModel.selectLocation(CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        viewModel.updateSearchRadius(60)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)

        answerLifestyleSteps(viewModel)
        XCTAssertEqual(viewModel.currentStep, .aloneTime)
        XCTAssertNil(viewModel.currentStep.next, "Time for yourself is the last question.")
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        XCTAssertTrue(viewModel.isCompleted)

        let draft = try XCTUnwrap(repository.loadProfile())
        XCTAssertEqual(draft.lifestyle.hasChildren, false)
        XCTAssertEqual(draft.lifestyle.futureChildren, .notSure)
        XCTAssertEqual(draft.lifestyle[.alcohol], SubstanceAnswer(ownLevel: 2, partnerMaximumLevel: 3))
        XCTAssertEqual(draft.lifestyle.aloneTime.importance, 4)
        XCTAssertTrue(draft.hasCompletedProfileCreation)
        XCTAssertTrue(draft.isAtLeast(age: 18))
        XCTAssertEqual(draft.preferredPartnerMinimumAge, 25)
        XCTAssertEqual(draft.preferredPartnerMaximumAge, 40)
        XCTAssertEqual(draft.heightCentimeters, 175)
        XCTAssertEqual(draft.preferredPartnerMinimumHeight, 165)
        XCTAssertEqual(draft.preferredPartnerMaximumHeight, 190)
        XCTAssertFalse(draft.autoMatching.isEnabled, "Auto matching starts switched off.")
        XCTAssertEqual(draft.gender, .man)
        XCTAssertEqual(draft.interestedIn, [.woman])
        XCTAssertEqual(draft.relationshipPreferences.selectedOptionIDs(for: .sexualArrangement), ["partnerOnly"])
        XCTAssertTrue(draft.languages.contains("es"))
        XCTAssertEqual(draft.preferredRadiusKilometers, 60)
        XCTAssertEqual(draft.matchLocation?.radiusKilometers, 60)
    }

    func testOnboardingRefusesToFinishWithoutAnAdultProfileCreation() {
        var draft = ProfileDraft()
        draft.dateOfBirth = Calendar.current.date(byAdding: .year, value: -15, to: Date())!
        draft.profileCreationCompletedAt = Date()
        let viewModel = OnboardingViewModel(repository: InMemoryProfileRepository(profile: draft))
        XCTAssertTrue(viewModel.requiresProfileCreation)
        XCTAssertFalse(viewModel.finishOnboarding())
    }

    func testLifestyleQuestionsEachNeedAnAnswer() {
        let viewModel = makeViewModel()
        for step in ProfileCreationStep.allCases where step >= .hasChildren {
            XCTAssertFalse(viewModel.isComplete(step), "\(step) has no preselection.")
        }
        viewModel.setFutureChildren(.yes)
        XCTAssertTrue(viewModel.isComplete(.futureChildren))
        viewModel.setOwnLevel(1, for: .smoking)
        XCTAssertFalse(viewModel.isComplete(.smoking), "The partner limit is part of the same answer.")
        viewModel.setPartnerMaximumLevel(0, for: .smoking)
        XCTAssertTrue(viewModel.isComplete(.smoking))
        viewModel.setOwnLevel(99, for: .smoking)
        XCTAssertEqual(viewModel.state.lifestyle[.smoking].ownLevel, 1, "Levels outside the scale are ignored.")
    }

    func testPartnerLimitAcceptsEveryLowerFrequency() {
        let answer = SubstanceAnswer(ownLevel: 0, partnerMaximumLevel: 2)
        XCTAssertTrue(answer.accepts(partnerLevel: 0))
        XCTAssertTrue(answer.accepts(partnerLevel: 2))
        XCTAssertFalse(answer.accepts(partnerLevel: 3))
        XCTAssertFalse(SubstanceAnswer().accepts(partnerLevel: 0), "No limit set accepts nothing yet.")
        XCTAssertEqual(Substance.drugs.levels, [
            "Never", "About once a year", "About once every 3 months",
            "About once a month", "About once a week", "Several times a week"
        ])
        XCTAssertEqual(Substance.alcohol.levels.first, "Never")
    }

    func testLevelsMissingFromARevisedScaleReadAsUnanswered() throws {
        let json = #"{"substances":{"drugs":{"ownLevel":6,"partnerMaximumLevel":2}},"aloneTime":{"isPartnerCustomized":false}}"#
        let answers = try JSONDecoder().decode(LifestyleAnswers.self, from: Data(json.utf8))
        XCTAssertNil(answers[.drugs].ownLevel)
        XCTAssertEqual(answers[.drugs].partnerMaximumLevel, 2)
    }

    func testPartnerScaleFollowsOwnAnswerUntilAdjusted() {
        let viewModel = makeViewModel()
        viewModel.setAloneTimeOwn(4)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.partner, 4, "The partner answer is prefilled.")
        viewModel.setAloneTimeOwn(2)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.partner, 2)
        viewModel.setAloneTimePartner(5)
        viewModel.setAloneTimeOwn(1)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.partner, 5, "An adjusted partner answer is kept.")
        XCTAssertFalse(viewModel.isComplete(.aloneTime), "Importance is still required.")
        viewModel.setAloneTimeImportance(3)
        XCTAssertTrue(viewModel.isComplete(.aloneTime))
        viewModel.setAloneTimeImportance(6)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.importance, 3)
    }

    func testEditingOneAnswerSavesTheWholeProfileAgain() throws {
        let store = InMemoryProfileCreationStore()
        let repository = InMemoryProfileRepository()
        completeProfile(makeViewModel(store: store, repository: repository))

        let relaunched = makeViewModel(store: store, repository: repository)
        XCTAssertTrue(relaunched.isCompleted, "A finished profile reopens on its completed screen.")
        relaunched.beginEditing(.drugs)
        XCTAssertEqual(relaunched.currentStep, .drugs)
        XCTAssertEqual(relaunched.editingStep, .drugs)
        relaunched.setPartnerMaximumLevel(0, for: .drugs)
        XCTAssertEqual(store.load()?.lifestyle[.drugs].partnerMaximumLevel, 3, "Unsaved changes are not stored.")

        XCTAssertEqual(relaunched.submitCurrentStep(), .completed)
        XCTAssertNil(relaunched.editingStep)
        XCTAssertTrue(relaunched.isCompleted)
        XCTAssertEqual(store.load()?.lifestyle[.drugs].partnerMaximumLevel, 0)
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).lifestyle[.drugs].partnerMaximumLevel, 0)
    }

    func testCancellingAnEditRestoresTheSavedAnswer() {
        let store = InMemoryProfileCreationStore()
        let viewModel = makeViewModel(store: store)
        completeProfile(viewModel)

        viewModel.beginEditing(.height)
        viewModel.updateHeight(190)
        viewModel.cancelEditing()
        XCTAssertNil(viewModel.editingStep)
        XCTAssertEqual(viewModel.state.heightCentimeters, 175)
        XCTAssertTrue(viewModel.isCompleted)
    }

    func testEditingTheBirthdayValidatesItAgain() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)

        viewModel.beginEditing(.dateOfBirth)
        XCTAssertEqual(viewModel.birthDateSelection, .init(year: 1996, month: 4, day: 21))
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed, "An unchanged adult birthday saves.")

        viewModel.beginEditing(.dateOfBirth)
        viewModel.updateBirthDate(.init(year: 2012, month: 4, day: 21))
        XCTAssertEqual(viewModel.submitCurrentStep(), .underage)
        XCTAssertTrue(viewModel.isUnderageLocked)
        XCTAssertFalse(viewModel.isCompleted, "Editing cannot keep a minor's profile complete.")
        XCTAssertNil(viewModel.editingStep)
    }

    func testOverviewSummarisesEveryAnswer() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)
        let state = viewModel.state
        for step in ProfileCreationStep.allCases {
            XCTAssertNotEqual(state.summary(for: step, today: today).value, "Not answered", "\(step)")
        }
        XCTAssertEqual(state.summary(for: .partnerAgeRange, today: today).value, "25–40 years")
        XCTAssertEqual(state.summary(for: .height, today: today).value, "175 cm")
        XCTAssertEqual(state.summary(for: .partnerHeightRange, today: today).value, "173–207 cm")
        XCTAssertEqual(state.summary(for: .aloneTime, today: today).compact, "You: 3 · partner: 3, important")
        XCTAssertNotNil(ProfileCreationStep.aloneTime.subtitle, "Time for yourself explains its scale.")
        XCTAssertEqual(state.summary(for: .alcohol, today: today).compact,
                       "1–3 times a month · partner at most about once a week")
        XCTAssertEqual(state.summary(for: .location, today: today).detail, "within 60 km")
    }

    func testStepsThatNoLongerExistReopenTheBirthday() throws {
        let decoded = try JSONDecoder().decode([ProfileCreationStep].self, from: Data("[12, 99]".utf8))
        XCTAssertEqual(decoded, [.alcohol, .dateOfBirth])
    }

    func testStatesSavedBeforeLifestyleQuestionsStillDecode() throws {
        let state = ProfileCreationState(today: today, applicationLanguage: "en")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "storedLifestyle")
        let decoded = try JSONDecoder().decode(ProfileCreationState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.lifestyle, LifestyleAnswers())
    }

    func testDealbreakersListTheBasicsInQuestionOrder() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)
        viewModel.beginEditing(.futureChildren)
        viewModel.setFutureChildren(.yes)
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)

        let language = LanguageCatalog.option(for: viewModel.state.languages[0]).name
        let dealbreakers = viewModel.dealbreakers
        XCTAssertEqual(dealbreakers.heading,
                       "Even if your potential partner matches 100% on personality, you will not be matched if she:")
        XCTAssertEqual(dealbreakers.lines, [
            "Is 24 or younger, or 41 or older",
            "Is 172 cm or shorter, or 208 cm or taller",
            "Doesn’t speak \(language)",
            "Lives more than 60 km away",
            "Doesn’t want kids",
            "Drinks alcohol 2–3 times a week or more often",
            "Smokes or vapes daily or more often",
            "Uses cannabis or other drugs about once a week or more often"
        ])
    }

    func testDealbreakersLeaveOutOpenLimits() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)
        for step in [ProfileCreationStep.partnerAgeRange, .partnerHeightRange, .partnerHasChildren, .alcohol] {
            viewModel.beginEditing(step)
            switch step {
            case .partnerAgeRange: viewModel.updatePartnerAgeRange(minimum: 18, maximum: 30)
            case .partnerHeightRange: viewModel.updatePartnerHeightRange(minimum: 0, maximum: 999)
            case .partnerHasChildren: viewModel.setOpenToPartnerWithChildren(false)
            default: viewModel.setPartnerMaximumLevel(Substance.alcohol.levels.count - 1, for: .alcohol)
            }
            XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        }
        viewModel.togglePartnerGender(.man)

        let lines = viewModel.dealbreakers.lines
        XCTAssertEqual(viewModel.dealbreakers.pronoun, .they)
        XCTAssertEqual(lines.first, "Are 31 or older", "No lower age is set at 18.")
        XCTAssertFalse(lines.contains { $0.contains("cm") }, "Any height rules no one out.")
        XCTAssertTrue(lines.contains("Have kids"))
        XCTAssertFalse(lines.contains { $0.contains("alcohol") }, "The most frequent level allowed rules no one out.")
        XCTAssertEqual(viewModel.state.partnerHeightRange, .any)
    }

    func testAutoMatchingNeedsAPhotoAndBothScores() throws {
        let repository = InMemoryProfileRepository()
        let store = InMemoryProfileCreationStore()
        let viewModel = makeViewModel(store: store, repository: repository)
        completeProfile(viewModel)
        XCTAssertFalse(viewModel.state.autoMatching.isEnabled)

        viewModel.setOwnAttractiveness(4)
        viewModel.setPartnerAppearanceImportance(9)
        XCTAssertFalse(viewModel.joinAutoMatching(), "A photo and both scores are required.")
        viewModel.setPartnerAppearanceImportance(2)
        XCTAssertFalse(viewModel.joinAutoMatching())

        let photo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        XCTAssertNil(viewModel.setAutoMatchingPhoto(photo))
        XCTAssertNotNil(viewModel.autoMatchingPhoto)
        XCTAssertNotNil(viewModel.setAutoMatchingPhoto(Data("not an image".utf8)))
        XCTAssertNil(viewModel.setAutoMatchingPhoto(photo))
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).photos.count, 1, "A new photo replaces the previous one.")

        viewModel.setMinimumMatchPercent(97)
        XCTAssertEqual(viewModel.state.autoMatching.minimumMatchPercent, 90)
        viewModel.setMinimumMatchPercent(63)
        XCTAssertEqual(viewModel.state.autoMatching.minimumMatchPercent, 65)
        XCTAssertTrue(viewModel.joinAutoMatching())

        let draft = try XCTUnwrap(repository.loadProfile())
        XCTAssertTrue(draft.autoMatching.isEnabled)
        XCTAssertEqual(draft.autoMatching.ownAttractiveness, 4)
        XCTAssertEqual(draft.autoMatching.partnerAppearanceImportance, 2)
        XCTAssertEqual(draft.autoMatching.minimumMatchPercent, 65)
        XCTAssertEqual(draft.lifestyle[.alcohol].partnerMaximumLevel, 3, "Joining keeps the rest of the profile.")
        XCTAssertEqual(store.load()?.autoMatching.isEnabled, true)

        viewModel.leaveAutoMatching()
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).autoMatching.isEnabled, false)
        XCTAssertEqual(viewModel.state.autoMatching.ownAttractiveness, 4, "Switching off keeps the answers.")
    }

    func testDraftsSavedBeforeAutoMatchingStillDecode() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileDraft())) as? [String: Any])
        json.removeValue(forKey: "autoMatching")
        json.removeValue(forKey: "preferredPartnerMinimumHeight")
        let decoded = try JSONDecoder().decode(ProfileDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.autoMatching, AutoMatchingSettings())
        XCTAssertNil(decoded.preferredPartnerMinimumHeight)
    }

    private func answerLifestyleSteps(_ viewModel: ProfileCreationViewModel) {
        XCTAssertEqual(viewModel.currentStep, .hasChildren)
        XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)
        viewModel.setHasChildren(false)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        viewModel.setOpenToPartnerWithChildren(true)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        viewModel.setFutureChildren(.notSure)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        for substance in Substance.allCases {
            XCTAssertEqual(viewModel.currentStep.substance, substance)
            viewModel.setOwnLevel(2, for: substance)
            XCTAssertEqual(viewModel.submitCurrentStep(), .rejected, "The partner limit is still open.")
            viewModel.setPartnerMaximumLevel(3, for: substance)
            XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        }
        viewModel.setAloneTimeOwn(3)
        viewModel.setAloneTimeImportance(4)
    }

    private func completeProfile(_ viewModel: ProfileCreationViewModel) {
        advancePastBirthday(viewModel)
        viewModel.updatePartnerAgeRange(minimum: 25, maximum: 40)
        viewModel.submitCurrentStep()
        viewModel.submitCurrentStep()
        viewModel.updatePartnerHeightRange(minimum: 173, maximum: 207)
        viewModel.submitCurrentStep()
        viewModel.selectGender(.man)
        viewModel.submitCurrentStep()
        viewModel.togglePartnerGender(.woman)
        viewModel.submitCurrentStep()
        viewModel.selectPreference("partnerOnly", in: .sexualArrangement)
        viewModel.submitCurrentStep()
        viewModel.submitCurrentStep()
        viewModel.selectLocation(CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        viewModel.updateSearchRadius(60)
        viewModel.submitCurrentStep()
        answerLifestyleSteps(viewModel)
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
    }

    private func advancePastBirthday(_ viewModel: ProfileCreationViewModel) {
        viewModel.updateBirthDate(.init(year: 1996, month: 4, day: 21))
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.partnerAgeRange, PartnerAgeRange(minimum: 25, maximum: 35))
    }
}
