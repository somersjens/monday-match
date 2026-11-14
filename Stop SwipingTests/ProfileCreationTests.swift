import CoreLocation
import XCTest
import UIKit
@testable import Stop_Swiping

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
        XCTAssertEqual(HeightRules.clamped(40), 50)
        XCTAssertEqual(HeightRules.clamped(80), 80)
        XCTAssertEqual(HeightRules.clamped(300), 250)
        XCTAssertEqual(HeightRules.imperialDescription(centimeters: 175), "5′ 9″")
        XCTAssertEqual(SearchRadiusRules.clamped(0), 1)
        XCTAssertEqual(SearchRadiusRules.clamped(500), 200)
    }

    func testManualHeightInputClampsWholeNumbersAndRejectsInvalidText() {
        XCTAssertEqual(HeightRules.centimeters(from: " 175 "), 175)
        XCTAssertEqual(HeightRules.centimeters(from: "50"), 50)
        XCTAssertEqual(HeightRules.centimeters(from: "250"), 250)
        XCTAssertEqual(HeightRules.centimeters(from: "-10"), 50)
        XCTAssertEqual(HeightRules.centimeters(from: "300"), 250)
        XCTAssertEqual(HeightRules.centimeters(from: String(repeating: "9", count: 100)), 250)
        XCTAssertEqual(HeightRules.centimeters(from: "-" + String(repeating: "9", count: 100)), 50)
        for input in ["", " ", "-", "abc", "175 cm", "175.5"] {
            XCTAssertNil(HeightRules.centimeters(from: input), input)
        }
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

    func testEditingEitherPartnerHeightMovesTheOtherEndpointOnlyWhenCrossed() {
        let viewModel = makeViewModel()
        viewModel.updatePartnerHeightRange(minimum: 165, maximum: 190)
        viewModel.updatePartnerMinimumHeight(180)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 180, maximum: 190))
        viewModel.updatePartnerMinimumHeight(210)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 210, maximum: 210))
        viewModel.updatePartnerMaximumHeight(160)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 160, maximum: 160))
        viewModel.updatePartnerMaximumHeight(180)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 160, maximum: 180))
        viewModel.updatePartnerMinimumHeight(999)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 250, maximum: 250))
        viewModel.updatePartnerMaximumHeight(-1)
        XCTAssertEqual(viewModel.state.partnerHeightRange, PartnerHeightRange(minimum: 50, maximum: 50))
        viewModel.updatePartnerMinimumHeight(-1)
        viewModel.updatePartnerMaximumHeight(999)
        XCTAssertEqual(viewModel.state.partnerHeightRange, .any)
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
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        viewModel.addLanguage("es")
        viewModel.submitCurrentStep()

        XCTAssertEqual(viewModel.currentStep, .location)
        XCTAssertFalse(viewModel.canContinue, "A location is required.")
        viewModel.selectLocation(CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        viewModel.updateSearchRadius(60)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)

        answerLifestyleSteps(viewModel)
        XCTAssertEqual(viewModel.currentStep, .aloneTime)
        XCTAssertEqual(viewModel.currentStep.next, .sharedHobbies)
        answerCompatibilitySteps(viewModel)
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
        XCTAssertTrue(viewModel.isComplete(.aloneTime), "Importance defaults to 3.")
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.importance, 3)
        viewModel.setAloneTimeImportance(3)
        XCTAssertTrue(viewModel.isComplete(.aloneTime))
        viewModel.setAloneTimeImportance(6)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.importance, 3)
    }

    func testSingleChoicesAreReadyToAdvanceOnSelection() {
        let viewModel = makeViewModel()
        advancePastBirthday(viewModel)
        for _ in 0..<3 { viewModel.submitCurrentStep() }
        XCTAssertEqual(viewModel.currentStep, .gender)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.selectGender(.woman)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        viewModel.togglePartnerGender(.man)
        viewModel.submitCurrentStep()

        XCTAssertEqual(viewModel.currentStep, .sexualArrangement)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.selectPreference("partnerOnly", in: .sexualArrangement)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)

        viewModel.submitCurrentStep()
        viewModel.skipReligionPhase()
        viewModel.skipReligionPhase()
        viewModel.submitCurrentStep()
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection, "Location is confirmed manually.")
        viewModel.selectLocation(CLLocationCoordinate2D(latitude: 51, longitude: 3), source: .map)
        viewModel.submitCurrentStep()
        viewModel.setHasChildren(false)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection, "No is also a complete answer.")
        viewModel.submitCurrentStep()
        viewModel.setOpenToPartnerWithChildren(true)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.submitCurrentStep()
        viewModel.setFutureChildren(.notSure)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)
    }

    func testMultipleChoicesWaitUntilEveryVisibleOptionIsSelected() {
        let viewModel = makeViewModel()
        advancePastBirthday(viewModel)
        for _ in 0..<3 { viewModel.submitCurrentStep() }
        viewModel.selectGender(.man)
        viewModel.submitCurrentStep()
        XCTAssertEqual(viewModel.currentStep, .partnerGenders)
        for gender in GenderIdentity.onboardingOptions.dropLast() {
            viewModel.togglePartnerGender(gender)
            XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
            XCTAssertTrue(viewModel.canContinue, "A subset can still be confirmed manually.")
        }
        viewModel.togglePartnerGender(GenderIdentity.onboardingOptions.last!)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.togglePartnerGender(.man)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
    }

    func testDataDrivenMultipleChoicesAlsoWaitForEveryOption() {
        let question = RelationshipPreferenceQuestion(
            id: "multiple", prompt: "Choose", selectionMode: .multiple,
            options: [.init(id: "a", title: "A"), .init(id: "b", title: "B")]
        )
        var answers = RelationshipPreferenceAnswers()
        XCTAssertFalse(answers.shouldAutoAdvance(question))
        answers.select("a", in: question)
        XCTAssertFalse(answers.shouldAutoAdvance(question))
        answers.select("b", in: question)
        XCTAssertTrue(answers.shouldAutoAdvance(question))
        answers.select("a", in: question)
        XCTAssertFalse(answers.shouldAutoAdvance(question))
    }

    func testThreePillarsOnlyAutoAdvanceWithDifferentPartnerAndNonDefaultImportance() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)
        while viewModel.currentStep != .aloneTime { XCTAssertTrue(viewModel.goBack()) }
        XCTAssertEqual(viewModel.currentStep, .aloneTime)
        viewModel.setAloneTimeImportance(3)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.setAloneTimeOwn(2)
        XCTAssertEqual(viewModel.state.lifestyle.aloneTime.partner, 2)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.setAloneTimePartner(5)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection, "Importance still has its default value.")
        viewModel.setAloneTimeImportance(4)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.setAloneTimePartner(2)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection, "Equal own and partner values require Continue.")
        viewModel.setAloneTimeOwn(1)
        XCTAssertTrue(viewModel.shouldAutoAdvanceAfterAnswerSelection, "The fields can be chosen in any order.")
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .sharedHobbies)

        viewModel.beginEditing(.aloneTime)
        viewModel.setAloneTimePartner(5)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection, "Edits retain the explicit Save action.")
    }

    func testDefaultImportanceAlsoAppliesToOlderSavedAnswers() throws {
        XCTAssertEqual(CompatibilityScaleAnswer().importance, 3)
        XCTAssertFalse(CompatibilityScaleAnswer().isComplete)
        for json in [#"{}"#, #"{"importance":null}"#, #"{"own":2,"partner":2}"#] {
            let answer = try JSONDecoder().decode(CompatibilityScaleAnswer.self, from: Data(json.utf8))
            XCTAssertEqual(answer.importance, 3)
            XCTAssertFalse(answer.hasCustomValuesForAutoAdvance)
        }
        let saved = CompatibilityScaleAnswer(own: 2, partner: 4, isPartnerCustomized: true, importance: 5)
        let decoded = try JSONDecoder().decode(CompatibilityScaleAnswer.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved, "An existing importance is preserved.")
    }

    func testExpandedCompatibilityAnswersStayIndependentAndSurviveRelaunch() throws {
        let viewModel = makeViewModel()
        let questions = CompatibilityScaleQuestion.all
        for (index, question) in questions.enumerated() {
            let own = index % 5 + 1
            let partner = (index + 2) % 5 + 1
            viewModel.setCompatibilityOwn(own, for: question)
            XCTAssertEqual(viewModel.state.lifestyle[question].partner, own)
            viewModel.setCompatibilityPartner(partner, for: question)
            viewModel.setCompatibilityOwn(own % 5 + 1, for: question)
            XCTAssertEqual(viewModel.state.lifestyle[question].partner, partner, "A customized partner answer stays independent.")
            viewModel.setCompatibilityImportance(index % 5 + 1, for: question)
            viewModel.setCompatibilityOwn(0, for: question)
            viewModel.setCompatibilityPartner(6, for: question)
            viewModel.setCompatibilityImportance(6, for: question)
        }
        let restored = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(viewModel.state))
        for (index, question) in questions.enumerated() {
            let answer = restored.lifestyle[question]
            XCTAssertEqual(answer.own, (index % 5 + 1) % 5 + 1)
            XCTAssertEqual(answer.partner, (index + 2) % 5 + 1)
            XCTAssertEqual(answer.importance, index % 5 + 1)
            XCTAssertTrue(answer.isPartnerCustomized)
            XCTAssertTrue(viewModel.isComplete(question.step))
        }
    }

    func testOlderLifestyleAnswersKeepTheirOriginalScaleAndLeaveNewTopicsUnanswered() throws {
        let json = #"{"substances":{},"aloneTime":{"own":2,"partner":4,"isPartnerCustomized":true,"importance":5}}"#
        let answers = try JSONDecoder().decode(LifestyleAnswers.self, from: Data(json.utf8))
        XCTAssertEqual(answers[CompatibilityScaleQuestion.aloneTime], answers.aloneTime)
        XCTAssertEqual(answers.aloneTime.own, 2)
        XCTAssertEqual(answers.aloneTime.partner, 4)
        XCTAssertEqual(answers.aloneTime.importance, 5)
        for question in CompatibilityScaleQuestion.all.dropFirst() {
            XCTAssertFalse(answers[question].isComplete)
            XCTAssertNil(answers[question].own)
            XCTAssertNil(answers[question].partner)
            XCTAssertEqual(answers[question].importance, 3)
        }
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("15".utf8)), .aloneTime)
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("16".utf8)), .religion)
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("19".utf8)), .physicalAffection)
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("54".utf8)), .sharedResponsibilities)
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("17".utf8)), .dateOfBirth,
                       "A retired question reopens the first step.")
    }

    func testEachNewCompatibilityQuestionSupportsSavingAndCancellingAnEdit() throws {
        let repository = InMemoryProfileRepository()
        let viewModel = makeViewModel(repository: repository)
        completeProfile(viewModel)
        for question in CompatibilityScaleQuestion.all.dropFirst() {
            viewModel.beginEditing(question.step)
            viewModel.setCompatibilityOwn(1, for: question)
            viewModel.setCompatibilityPartner(5, for: question)
            viewModel.setCompatibilityImportance(5, for: question)
            XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
            viewModel.cancelEditing()
            XCTAssertEqual(viewModel.state.lifestyle[question].own, 3)
            viewModel.beginEditing(question.step)
            viewModel.setCompatibilityPartner(1, for: question)
            XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
            XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).lifestyle[question].partner, 1)
        }
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

    func testAutoMatchingNeedsBothScoresAndVerifiesAnOptionalPhoto() throws {
        let repository = InMemoryProfileRepository()
        let store = InMemoryProfileCreationStore()
        let viewModel = makeViewModel(store: store, repository: repository)
        completeProfile(viewModel)
        authorizeMatching(viewModel)
        XCTAssertFalse(viewModel.state.autoMatching.isEnabled)

        XCTAssertFalse(viewModel.joinAutoMatching(), "Both scores are required.")
        viewModel.setOwnAttractiveness(4)
        XCTAssertFalse(viewModel.joinAutoMatching(), "The partner score is still required.")
        viewModel.setPartnerMinimumAttractiveness(2)
        XCTAssertTrue(viewModel.joinAutoMatching(), "Joining without a photo is allowed.")
        XCTAssertNil(try XCTUnwrap(repository.loadProfile()).autoMatching.photoID)
        XCTAssertTrue(viewModel.state.autoMatching.requiresVerifiedPartnerPhoto, "The partner requirement is independent of our own photo.")

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
        XCTAssertFalse(viewModel.joinAutoMatching(), "An uploaded photo must also pass live verification.")
        let reference = try XCTUnwrap(viewModel.autoMatchingReferencePhoto)
        viewModel.recordAutoMatchingPhotoVerification(.init(photoID: reference.id, imageData: reference.imageData, outcome: .match))
        XCTAssertTrue(viewModel.joinAutoMatching())

        let draft = try XCTUnwrap(repository.loadProfile())
        XCTAssertTrue(draft.autoMatching.isEnabled)
        XCTAssertEqual(draft.autoMatching.ownAttractiveness, 4)
        XCTAssertEqual(draft.autoMatching.partnerMinimumAttractiveness, 2)
        XCTAssertEqual(draft.autoMatching.minimumMatchPercent, 65)
        XCTAssertEqual(draft.lifestyle[.alcohol].partnerMaximumLevel, 3, "Joining keeps the rest of the profile.")
        XCTAssertEqual(store.load()?.autoMatching.isEnabled, true)

        viewModel.leaveAutoMatching()
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).autoMatching.isEnabled, false)
        XCTAssertEqual(viewModel.state.autoMatching.ownAttractiveness, 4, "Switching off keeps the answers.")

        XCTAssertNil(viewModel.setAutoMatchingPhoto(photo))
        XCTAssertFalse(viewModel.hasVerifiedAutoMatchingPhoto, "Replacing a photo invalidates its live scan.")
        XCTAssertFalse(viewModel.state.autoMatching.isEnabled)
        viewModel.recordAutoMatchingPhotoVerification(.init(photoID: reference.id, imageData: reference.imageData, outcome: .match))
        XCTAssertFalse(viewModel.hasVerifiedAutoMatchingPhoto, "A stale scan cannot verify a replacement photo.")
        XCTAssertFalse(viewModel.joinAutoMatching())
        XCTAssertFalse(try XCTUnwrap(repository.loadProfile()).autoMatching.isEnabled)
    }

    func testCompletedAutoMatchingSetupCanResumeAfterSwitchingOffAndRelaunching() throws {
        let repository = InMemoryProfileRepository()
        let store = InMemoryProfileCreationStore()
        let model = makeViewModel(store: store, repository: repository)
        completeProfile(model)
        authorizeMatching(model)
        model.setOwnAttractiveness(7)
        model.setPartnerMinimumAttractiveness(6)
        model.setMinimumMatchPercent(80)
        model.setRequiresVerifiedPartnerPhoto(false)
        XCTAssertFalse(model.canResumeAutoMatching, "Scores alone must not skip the first setup.")
        XCTAssertFalse(model.resumeAutoMatching())
        XCTAssertTrue(model.joinAutoMatching())
        model.leaveAutoMatching()
        let saved = model.state.autoMatching
        XCTAssertFalse(saved.isEnabled)
        XCTAssertTrue(saved.hasCompletedSetup)

        let restoredState = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(model.state))
        let relaunched = makeViewModel(store: InMemoryProfileCreationStore(state: restoredState), repository: repository)
        XCTAssertTrue(relaunched.canResumeAutoMatching)
        XCTAssertTrue(relaunched.resumeAutoMatching())
        var expected = saved
        expected.isEnabled = true
        XCTAssertEqual(relaunched.state.autoMatching, expected)
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).autoMatching, expected)
        relaunched.leaveAutoMatching()
        XCTAssertTrue(relaunched.resumeAutoMatching(), "Repeated switching stays immediate.")
    }

    func testVerifiedPhotoCanResumeAfterRelaunchButReplacementNeedsVerification() throws {
        let repository = InMemoryProfileRepository()
        let store = InMemoryProfileCreationStore()
        let model = makeViewModel(store: store, repository: repository)
        completeProfile(model)
        authorizeMatching(model)
        model.setOwnAttractiveness(7)
        model.setPartnerMinimumAttractiveness(6)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        XCTAssertNil(model.setAutoMatchingPhoto(data))
        let reference = try XCTUnwrap(model.autoMatchingReferencePhoto)
        model.recordAutoMatchingPhotoVerification(.init(photoID: reference.id, imageData: reference.imageData, outcome: .match))
        XCTAssertTrue(model.joinAutoMatching())
        model.leaveAutoMatching()
        let relaunched = makeViewModel(store: store, repository: repository)
        XCTAssertNil(relaunched.autoMatchingPhotoVerification)
        XCTAssertTrue(relaunched.resumeAutoMatching(), "An unchanged approved photo needs no repeat scan.")
        XCTAssertNil(relaunched.setAutoMatchingPhoto(data))
        XCTAssertFalse(relaunched.canResumeAutoMatching)
        XCTAssertFalse(relaunched.resumeAutoMatching())
        XCTAssertFalse(relaunched.joinAutoMatching())
    }

    func testPreviouslyEnabledSettingsMigrateToCompletedSetup() throws {
        var settings = AutoMatchingSettings()
        settings.ownAttractiveness = 7
        settings.partnerMinimumAttractiveness = 6
        settings.privacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.matching.version, acceptedAt: Date(), languageCode: "en")
        settings.isEnabled = true
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "hasCompletedSetup")
        let restored = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(restored.hasCompletedSetup)
        XCTAssertFalse(AutoMatchingSettings().hasCompletedSetup)
    }

    func testPartnerPhotoVerificationPreferencePersistsAndDefaultsOnForOlderSettings() throws {
        let repository = InMemoryProfileRepository()
        let store = InMemoryProfileCreationStore()
        let viewModel = makeViewModel(store: store, repository: repository)
        completeProfile(viewModel)
        authorizeMatching(viewModel)
        viewModel.setOwnAttractiveness(7)
        viewModel.setPartnerMinimumAttractiveness(6)
        viewModel.setRequiresVerifiedPartnerPhoto(false)
        XCTAssertTrue(viewModel.joinAutoMatching())
        let saved = try XCTUnwrap(repository.loadProfile())
        XCTAssertFalse(saved.autoMatching.requiresVerifiedPartnerPhoto)
        XCTAssertEqual(CloudProfile(draft: saved, photoURLs: []).requiresVerifiedPartnerPhoto, false)
        XCTAssertFalse(makeViewModel(store: store, repository: repository).state.autoMatching.requiresVerifiedPartnerPhoto)
        let decoded = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONEncoder().encode(saved.autoMatching))
        XCTAssertEqual(decoded, saved.autoMatching)
        XCTAssertTrue(decoded.isEnabled, "A saved photo-free opt-in stays enabled after decoding.")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        legacy.removeValue(forKey: "requiresVerifiedPartnerPhoto")
        let restored = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(restored.requiresVerifiedPartnerPhoto)
    }

    func testRemovingAutoMatchingPhotoLetsUserJoinWithoutDeletingOtherPhotos() throws {
        let repository = InMemoryProfileRepository()
        let viewModel = makeViewModel(repository: repository)
        completeProfile(viewModel)
        authorizeMatching(viewModel)
        viewModel.setOwnAttractiveness(7)
        viewModel.setPartnerMinimumAttractiveness(6)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        XCTAssertNil(viewModel.setAutoMatchingPhoto(data))
        let reference = try XCTUnwrap(viewModel.autoMatchingReferencePhoto)
        viewModel.recordAutoMatchingPhotoVerification(.init(photoID: reference.id, imageData: reference.imageData, outcome: .match))
        var draft = try XCTUnwrap(repository.loadProfile())
        let other = ProfilePhoto(imageData: data, order: 1)
        draft.photos.append(other)
        try repository.saveProfile(draft)
        XCTAssertNil(viewModel.removeAutoMatchingPhoto())
        XCTAssertNil(viewModel.autoMatchingReferencePhoto)
        XCTAssertNil(viewModel.autoMatchingPhotoVerification)
        XCTAssertEqual(try XCTUnwrap(repository.loadProfile()).photos.map(\.id), [other.id])
        XCTAssertTrue(viewModel.joinAutoMatching())
    }

    func testEditingAnExclusionUpdatesItsSummaryOnlyAfterSave() {
        let viewModel = makeViewModel()
        completeProfile(viewModel)
        let original = viewModel.dealbreakers
        XCTAssertTrue(original.entries.allSatisfy { MatchDealbreakers.editableSteps.contains($0.step) })
        XCTAssertEqual(Set(original.entries.map(\.step)).count, original.entries.count)
        viewModel.beginEditing(.partnerAgeRange)
        viewModel.updatePartnerAgeRange(minimum: 28, maximum: 35)
        viewModel.cancelEditing()
        XCTAssertEqual(viewModel.dealbreakers, original)
        viewModel.beginEditing(.partnerAgeRange)
        viewModel.updatePartnerAgeRange(minimum: 28, maximum: 35)
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        XCTAssertNotEqual(viewModel.dealbreakers, original)
        XCTAssertTrue(viewModel.dealbreakers.entries.contains { $0.step == .partnerAgeRange && $0.text.contains("36") })
    }

    func testAppearanceScoresAcceptOneThroughTenAndRejectValuesOutsideTheScale() {
        let viewModel = makeViewModel()
        for score in 1...10 {
            viewModel.setOwnAttractiveness(score)
            viewModel.setPartnerMinimumAttractiveness(score)
            XCTAssertEqual(viewModel.state.autoMatching.ownAttractiveness, score)
            XCTAssertEqual(viewModel.state.autoMatching.partnerMinimumAttractiveness, score)
        }
        for invalidScore in [0, 11] {
            viewModel.setOwnAttractiveness(invalidScore)
            viewModel.setPartnerMinimumAttractiveness(invalidScore)
            XCTAssertEqual(viewModel.state.autoMatching.ownAttractiveness, 10)
            XCTAssertEqual(viewModel.state.autoMatching.partnerMinimumAttractiveness, 10)
        }
    }

    func testAppearanceScoresRoundTripAndReachTheCloudProfile() throws {
        var settings = AutoMatchingSettings()
        settings.photoID = UUID()
        settings.ownAttractiveness = 10
        settings.partnerMinimumAttractiveness = 7
        settings.privacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.matching.version, acceptedAt: Date(), languageCode: "en")
        settings.isEnabled = true
        let decoded = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        XCTAssertTrue(decoded.isReady)

        var draft = ProfileDraft()
        draft.autoMatching = decoded
        let cloud = CloudProfile(draft: draft, photoURLs: [])
        XCTAssertEqual(cloud.ownAttractiveness, 10)
        XCTAssertEqual(cloud.partnerMinimumAttractiveness, 7)
        let cloudJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cloud)) as? [String: Any])
        XCTAssertEqual(cloudJSON["partnerMinimumAttractiveness"] as? Int, 7)
        XCTAssertNil(cloudJSON["partnerAppearanceImportance"])
    }

    func testLegacyAppearanceImportanceIsNotReusedAsAMinimum() throws {
        let photoID = UUID()
        let legacy: [String: Any] = [
            "isEnabled": true,
            "photoID": photoID.uuidString,
            "ownAttractiveness": 4,
            "partnerAppearanceImportance": 5,
            "minimumMatchPercent": 80
        ]
        let decoded = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.photoID, photoID)
        XCTAssertEqual(decoded.minimumMatchPercent, 80)
        XCTAssertNil(decoded.ownAttractiveness)
        XCTAssertNil(decoded.partnerMinimumAttractiveness)
        XCTAssertFalse(decoded.isReady)
        XCTAssertFalse(decoded.isEnabled)
    }

    func testInvalidSavedAppearanceScoresRequireAValidAnswer() throws {
        let invalid: [String: Any] = [
            "appearanceScaleVersion": 1,
            "isEnabled": true,
            "photoID": UUID().uuidString,
            "ownAttractiveness": 11,
            "partnerMinimumAttractiveness": 0,
            "minimumMatchPercent": 70
        ]
        let decoded = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONSerialization.data(withJSONObject: invalid))
        XCTAssertNil(decoded.ownAttractiveness)
        XCTAssertNil(decoded.partnerMinimumAttractiveness)
        XCTAssertFalse(decoded.isReady)
        XCTAssertFalse(decoded.isEnabled)
    }

    func testDraftsSavedBeforeAutoMatchingStillDecode() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileDraft())) as? [String: Any])
        json.removeValue(forKey: "autoMatching")
        json.removeValue(forKey: "preferredPartnerMinimumHeight")
        let decoded = try JSONDecoder().decode(ProfileDraft.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.autoMatching, AutoMatchingSettings())
        XCTAssertNil(decoded.preferredPartnerMinimumHeight)
    }

    func testReligionFitsBetweenArrangementAndLanguagesWithoutChangingStoredStepIDs() throws {
        XCTAssertEqual(ProfileCreationStep.sexualArrangement.next, .religion)
        XCTAssertEqual(ProfileCreationStep.religion.previous, .sexualArrangement)
        XCTAssertEqual(ProfileCreationStep.religion.next, .languages)
        XCTAssertEqual(ProfileCreationStep.languages.previous, .religion)
        XCTAssertLessThan(ProfileCreationStep.religion, .languages)
        XCTAssertEqual(try JSONDecoder().decode(ProfileCreationStep.self, from: Data("7".utf8)), .languages)
        for (index, step) in ProfileCreationStep.allCases.enumerated() {
            XCTAssertEqual(step.number, index + 1)
            XCTAssertEqual(step.next, ProfileCreationStep.allCases.dropFirst(index + 1).first)
            XCTAssertEqual(step.previous, ProfileCreationStep.allCases.prefix(index).last)
        }
    }

    func testReligionSelectionIsOptionalDeselectableAndDoesNotAutoAdvance() {
        let viewModel = religionViewModel()
        XCTAssertTrue(viewModel.canContinue)
        XCTAssertNil(viewModel.state.religion.own)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, Set(Religion.allCases))
        viewModel.toggleOwnReligion(.christian)
        XCTAssertEqual(viewModel.state.religion.own, .christian)
        XCTAssertFalse(viewModel.shouldAutoAdvanceAfterAnswerSelection)
        viewModel.toggleOwnReligion(.muslim)
        XCTAssertEqual(viewModel.state.religion.own, .muslim)
        viewModel.toggleOwnReligion(.muslim)
        XCTAssertNil(viewModel.state.religion.own)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .religion)
        XCTAssertEqual(viewModel.state.religionPhase, .partner)
        viewModel.togglePartnerReligion(.christian)
        viewModel.togglePartnerReligion(.jewish)
        XCTAssertFalse(viewModel.state.religion.acceptedPartnerReligions.contains(.christian))
        XCTAssertFalse(viewModel.state.religion.acceptedPartnerReligions.contains(.jewish))
        XCTAssertTrue(viewModel.state.religion.acceptedPartnerReligions.contains(.muslim))
        XCTAssertTrue(viewModel.goBack())
        XCTAssertEqual(viewModel.state.religionPhase, .own)
        XCTAssertEqual(viewModel.currentStep, .religion)
        XCTAssertTrue(viewModel.goBack())
        XCTAssertEqual(viewModel.currentStep, .sexualArrangement)
    }

    func testReligionSkippingOwnOnlyAdvancesToPartnerAndPartnerSkipResetsAllChoices() {
        let viewModel = religionViewModel()
        viewModel.toggleOwnReligion(.atheist)
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .religion)
        XCTAssertEqual(viewModel.state.religionPhase, .partner)
        XCTAssertNil(viewModel.state.religion.own)
        XCTAssertEqual(viewModel.state.religion.matchingReligion, .other)
        XCTAssertEqual(viewModel.state.summary(for: .religion, today: today).value, "Other/Skipped")
        viewModel.togglePartnerReligion(.other)
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        XCTAssertEqual(viewModel.currentStep, .languages)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, Set(Religion.allCases))
        XCTAssertEqual(viewModel.skipReligionPhase(), .rejected, "No other question can be skipped.")
    }

    func testReligionSaveKeepsSubsetAndEmptyPreferenceDefaultsToEveryone() {
        let viewModel = religionViewModel()
        viewModel.toggleOwnReligion(.spiritual)
        viewModel.submitCurrentStep()
        for religion in Religion.allCases where religion != .spiritual {
            viewModel.togglePartnerReligion(religion)
        }
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, [.spiritual])
        XCTAssertEqual(viewModel.state.summary(for: .religion, today: today).compact, "Spiritual · Partner: Spiritual")
        viewModel.goBack()
        viewModel.submitCurrentStep()
        viewModel.togglePartnerReligion(.spiritual)
        XCTAssertTrue(viewModel.state.religion.acceptedPartnerReligions.isEmpty)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, Set(Religion.allCases))
    }

    func testReligionPartnerPhaseResumesAfterRelaunch() throws {
        let viewModel = religionViewModel()
        viewModel.toggleOwnReligion(.hindu)
        viewModel.submitCurrentStep()
        viewModel.togglePartnerReligion(.atheist)
        viewModel.persist()
        let decoded = try JSONDecoder().decode(ProfileCreationState.self, from: JSONEncoder().encode(viewModel.state))
        let resumed = makeViewModel(store: InMemoryProfileCreationStore(state: decoded))
        XCTAssertEqual(resumed.currentStep, .religion)
        XCTAssertEqual(resumed.state.religionPhase, .partner)
        XCTAssertEqual(resumed.state.religion.own, .hindu)
        XCTAssertFalse(resumed.state.religion.acceptedPartnerReligions.contains(.atheist))
        XCTAssertEqual(resumed.submitCurrentStep(), .advanced)
        XCTAssertEqual(resumed.currentStep, .languages)
    }

    func testReligionEditsSaveBothPartsTogetherAndCancelRestoresBoth() throws {
        let store = InMemoryProfileCreationStore()
        let repository = InMemoryProfileRepository()
        let viewModel = makeViewModel(store: store, repository: repository)
        completeProfile(viewModel)
        viewModel.beginEditing(.religion)
        viewModel.toggleOwnReligion(.buddhist)
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced, "The first part must never finish an edit.")
        XCTAssertEqual(viewModel.editingStep, .religion)
        viewModel.togglePartnerReligion(.agnostic)
        viewModel.persist()
        XCTAssertNil(store.load()?.religion.own, "An edit remains unsaved until Save on the second part.")
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        XCTAssertNil(viewModel.editingStep)
        XCTAssertEqual(store.load()?.religion.own, .buddhist)
        let draft = try XCTUnwrap(repository.loadProfile())
        XCTAssertEqual(draft.religion, viewModel.state.religion)
        XCTAssertFalse(draft.religion.acceptedPartnerReligions.contains(.agnostic))

        viewModel.beginEditing(.religion)
        viewModel.skipReligionPhase()
        viewModel.togglePartnerReligion(.agnostic)
        viewModel.cancelEditing()
        XCTAssertEqual(viewModel.state.religion, draft.religion)
    }

    func testReligionMatchingRequiresReciprocalAcceptanceForEveryPair() {
        for own in Religion.allCases {
            for partner in Religion.allCases {
                let a = ReligionAnswers(own: own, acceptedPartnerReligions: [partner])
                let b = ReligionAnswers(own: partner, acceptedPartnerReligions: [own])
                XCTAssertTrue(a.isMutuallyCompatible(with: b))
                XCTAssertTrue(b.isMutuallyCompatible(with: a))
                let rejected = Religion.allCases.first { $0 != own }!
                let c = ReligionAnswers(own: partner, acceptedPartnerReligions: [rejected])
                XCTAssertFalse(a.isMutuallyCompatible(with: c))
                XCTAssertFalse(c.isMutuallyCompatible(with: a), "A one-sided preference cannot create a match.")
            }
        }
        let skipped = ReligionAnswers()
        XCTAssertTrue(skipped.isMutuallyCompatible(with: ReligionAnswers(own: .christian, acceptedPartnerReligions: [.other])))
        XCTAssertFalse(skipped.isMutuallyCompatible(with: ReligionAnswers(own: .christian, acceptedPartnerReligions: [.atheist])))
        XCTAssertTrue(skipped.isMutuallyCompatible(with: ReligionAnswers(own: .atheist, acceptedPartnerReligions: [])))
        XCTAssertNotEqual(ReligionAnswers(own: Religion.none).matchingReligion, skipped.matchingReligion)
    }

    func testReligionDefaultsForLegacyStateDraftAndCloudAndNormalizedCloudWrites() throws {
        let state = ProfileCreationState(today: today, applicationLanguage: "en")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "storedReligion")
        json.removeValue(forKey: "storedReligionPhase")
        let decoded = try JSONDecoder().decode(ProfileCreationState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.religion, ReligionAnswers())
        XCTAssertEqual(decoded.religionPhase, .own)

        var draftJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileDraft())) as? [String: Any])
        draftJSON.removeValue(forKey: "religion")
        let draft = try JSONDecoder().decode(ProfileDraft.self, from: JSONSerialization.data(withJSONObject: draftJSON))
        XCTAssertEqual(draft.religion, ReligionAnswers())
        var partner = ProfileDraft()
        partner.religion = ReligionAnswers(own: .muslim, acceptedPartnerReligions: [.other])
        XCTAssertTrue(draft.isReligionCompatible(with: partner))
        let cloud = CloudProfile(draft: draft, photoURLs: [])
        let partnerCloud = CloudProfile(draft: partner, photoURLs: [])
        XCTAssertEqual(cloud.religion, .other)
        XCTAssertEqual(Set(cloud.acceptedPartnerReligions ?? []), Set(Religion.allCases))
        XCTAssertTrue(cloud.isReligionCompatible(with: partnerCloud))
        partner.religion.acceptedPartnerReligions = [.christian]
        XCTAssertFalse(draft.isReligionCompatible(with: partner))
        XCTAssertFalse(cloud.isReligionCompatible(with: CloudProfile(draft: partner, photoURLs: [])))
        let roundTrip = try JSONDecoder().decode(CloudProfile.self, from: JSONEncoder().encode(cloud))
        XCTAssertEqual(roundTrip, cloud)
        var cloudJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cloud)) as? [String: Any])
        cloudJSON.removeValue(forKey: "religion")
        cloudJSON.removeValue(forKey: "acceptedPartnerReligions")
        let legacyCloud = try JSONDecoder().decode(CloudProfile.self, from: JSONSerialization.data(withJSONObject: cloudJSON))
        XCTAssertTrue(legacyCloud.isReligionCompatible(with: partnerCloud))
    }

    func testReligionRestrictionsAppearInDealbreakers() {
        let viewModel = religionViewModel()
        let originalLines = viewModel.dealbreakers.lines
        for religion in Religion.allCases where religion != .christian { viewModel.togglePartnerReligion(religion) }
        XCTAssertEqual(viewModel.dealbreakers.lines.count, originalLines.count + 1)
        XCTAssertTrue(viewModel.dealbreakers.lines.contains { $0.contains("Christian") })
        XCTAssertEqual(Religion.allCases.filter { $0.explanation != nil }, [.atheist, .agnostic])
    }

    func testContinueFocusesTheMissingScaleAnswerWithoutAdvancingOrFillingItIn() {
        for step in [ProfileCreationStep.alcohol, .smoking, .drugs] {
            for answeredSide in [PartnerPreferenceScale.Mode.own, .partner] {
                var state = ProfileCreationState(today: today, applicationLanguage: "en")
                state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
                state.currentStep = step
                let viewModel = makeViewModel(store: InMemoryProfileCreationStore(state: state))
                let substance = step.substance!
                XCTAssertFalse(viewModel.canContinue)
                XCTAssertEqual(viewModel.submitCurrentStep(), .rejected)

                if answeredSide == .own {
                    viewModel.setOwnLevel(2, for: substance)
                } else {
                    viewModel.setPartnerMaximumLevel(3, for: substance)
                }
                let answer = viewModel.state.lifestyle[substance]
                let expectedSide: PartnerPreferenceScale.Mode = answeredSide == .own ? .partner : .own
                viewModel.substanceMode = answeredSide
                XCTAssertTrue(viewModel.canContinue)
                XCTAssertFalse(viewModel.isComplete(step))
                let rejections = viewModel.rejectionCount

                for _ in 0..<2 {
                    XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
                    XCTAssertEqual(viewModel.substanceMode, expectedSide)
                    XCTAssertEqual(viewModel.currentStep, step)
                    XCTAssertEqual(viewModel.state.lifestyle[substance], answer)
                    XCTAssertEqual(viewModel.rejectionCount, rejections)
                }

                viewModel.setOwnLevel(2, for: substance)
                viewModel.setPartnerMaximumLevel(3, for: substance)
                XCTAssertTrue(viewModel.isComplete(step))
                XCTAssertNil(viewModel.missingSubstanceSide)
                XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
                XCTAssertEqual(viewModel.currentStep, step.next)
            }
        }
    }

    func testDirectReligionChoicesOnlyChangeTheirOwnSideAndKeepTheActiveTab() {
        let viewModel = religionViewModel()
        let partnerChoices = viewModel.state.religion.acceptedPartnerReligions
        viewModel.togglePartnerReligion(.christian)
        XCTAssertEqual(viewModel.state.religionPhase, .own)
        XCTAssertNil(viewModel.state.religion.own)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, partnerChoices.subtracting([.christian]))

        viewModel.setReligionPhase(.partner)
        let updatedPartnerChoices = viewModel.state.religion.acceptedPartnerReligions
        viewModel.toggleOwnReligion(.muslim)
        XCTAssertEqual(viewModel.state.religion.own, .muslim)
        XCTAssertEqual(viewModel.state.religionPhase, .partner)
        XCTAssertEqual(viewModel.state.religion.acceptedPartnerReligions, updatedPartnerChoices)
        viewModel.toggleOwnReligion(.muslim)
        XCTAssertNil(viewModel.state.religion.own)
        XCTAssertEqual(viewModel.state.religionPhase, .partner)
    }

    private func religionViewModel() -> ProfileCreationViewModel {
        var state = ProfileCreationState(today: today, applicationLanguage: "en")
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.currentStep = .religion
        return makeViewModel(store: InMemoryProfileCreationStore(state: state))
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
            XCTAssertEqual(viewModel.submitCurrentStep(), .advanced, "Continue opens the missing partner limit.")
            XCTAssertEqual(viewModel.currentStep.substance, substance, "The question stays open until both answers are set.")
            viewModel.setPartnerMaximumLevel(3, for: substance)
            XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        }
        viewModel.setAloneTimeOwn(3)
        viewModel.setAloneTimeImportance(4)
    }

    private func authorizeMatching(_ model: ProfileCreationViewModel) {
        XCTAssertTrue(model.setDisplayName("Alex"))
        model.acceptPrivacy(.profile)
        model.acknowledgeExplanation()
        model.acceptPrivacy(.matching)
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
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        XCTAssertEqual(viewModel.skipReligionPhase(), .advanced)
        viewModel.submitCurrentStep()
        viewModel.selectLocation(CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        viewModel.updateSearchRadius(60)
        viewModel.submitCurrentStep()
        answerLifestyleSteps(viewModel)
        answerCompatibilitySteps(viewModel)
    }

    private func answerCompatibilitySteps(_ viewModel: ProfileCreationViewModel) {
        for question in CompatibilityScaleQuestion.all {
            XCTAssertEqual(viewModel.currentStep, question.step)
            viewModel.setCompatibilityOwn(3, for: question)
            viewModel.setCompatibilityImportance(4, for: question)
            XCTAssertEqual(viewModel.submitCurrentStep(), question.step.next == nil ? .completed : .advanced)
        }
    }

    private func advancePastBirthday(_ viewModel: ProfileCreationViewModel) {
        viewModel.updateBirthDate(.init(year: 1996, month: 4, day: 21))
        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.partnerAgeRange, PartnerAgeRange(minimum: 25, maximum: 35))
    }
}
