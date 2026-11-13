import Combine
import CoreLocation
import Foundation

enum ProfileCreationFeedback: Equatable {
    case birthday
    case nonexistentDate(monthName: String, year: Int, days: Int)
    case futureDate
    case saveFailed(String)

    var message: String {
        switch self {
        case .birthday:
            L10n("Go celebrate your birthday, come back tomorrow.")
        case let .nonexistentDate(monthName, year, days):
            L10n("That date doesn’t exist. \(monthName) \(String(year)) has \(days) days.")
        case .futureDate:
            L10n("That date hasn’t happened yet.")
        case .saveFailed(let reason):
            L10n("Your answers couldn’t be saved. \(reason)")
        }
    }

    var symbol: String {
        switch self {
        case .birthday: "gift"
        case .nonexistentDate, .futureDate: "calendar.badge.exclamationmark"
        case .saveFailed: "exclamationmark.triangle"
        }
    }
}

enum ProfileCreationSubmission: Equatable {
    case advanced
    case rejected
    case underage
    case completed
}

@MainActor
final class ProfileCreationViewModel: ObservableObject {
    @Published private(set) var state: ProfileCreationState
    @Published private(set) var feedback: ProfileCreationFeedback?
    /// Increments on every rejected Continue, so the view can replay feedback.
    @Published private(set) var rejectionCount = 0
    /// Set while a single answer of a completed profile is being changed.
    @Published private(set) var editingStep: ProfileCreationStep?
    @Published private(set) var autoMatchingPhotoVerification: PhotoVerificationReceipt?
    @Published var substanceMode: PartnerPreferenceScale.Mode = .own
    /// The answers as they were before that change, restored on cancel.
    private var stateBeforeEditing: ProfileCreationState?

    let calendar: Calendar
    private let store: ProfileCreationStateStoring
    private let repository: ProfileRepository?
    private let now: () -> Date

    init(
        store: ProfileCreationStateStoring,
        repository: ProfileRepository?,
        calendar: Calendar? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.repository = repository
        let calendar = calendar ?? BirthDateRules.calendar
        self.calendar = calendar
        self.now = now

        let today = CalendarDate.today(calendar: calendar, now: now())
        var state = store.load() ?? ProfileCreationState(today: today, applicationLanguage: AppLocale.languageCode)
        // The picker always opens on today's local date unless a birthday was
        // already confirmed; an unconfirmed spin from a previous launch is dropped.
        state.birthDateBaseline = today
        state.birthDateSelection = state.dateOfBirth ?? today
        if state.dateOfBirth == nil || state.isUnderageLocked {
            state.currentStep = .dateOfBirth
        }
        if state.languages.isEmpty {
            state.languages = [AppLocale.languageCode]
        }
        self.state = state
        substanceMode = missingSubstanceSide ?? .own
    }

    var today: CalendarDate { .today(calendar: calendar, now: now()) }
    var currentStep: ProfileCreationStep { state.currentStep }
    var isUnderageLocked: Bool { state.isUnderageLocked }

    var canContinue: Bool {
        // Continue stays tappable on the birthday step so it can explain why
        // today's date, a nonexistent date, or a future date is not accepted.
        state.currentStep == .dateOfBirth || isComplete(state.currentStep) || missingSubstanceSide != nil
    }

    /// A partial answer enables Continue to focus the unanswered half,
    /// while completion still requires both values.
    var missingSubstanceSide: PartnerPreferenceScale.Mode? {
        guard let substance = currentStep.substance else { return nil }
        let answer = state.lifestyle[substance]
        switch (answer.ownLevel, answer.partnerMaximumLevel) {
        case (.some, .none): return .partner
        case (.none, .some): return .own
        default: return nil
        }
    }

    func isComplete(_ step: ProfileCreationStep) -> Bool {
        switch step {
        case .dateOfBirth:
            guard let birth = state.dateOfBirth else { return false }
            return BirthDateRules.age(of: birth, on: today) >= BirthDateRules.minimumAge
        case .partnerAgeRange:
            return state.partnerAgeRange != nil
        case .height:
            return HeightRules.range.contains(state.heightCentimeters)
        case .partnerHeightRange:
            return PartnerHeightRules.bounds.contains(state.partnerHeightRange.minimum)
                && PartnerHeightRules.bounds.contains(state.partnerHeightRange.maximum)
        case .gender:
            return state.gender != nil
        case .partnerGenders:
            return !state.partnerGenders.isEmpty
        case .sexualArrangement:
            return state.relationshipPreferences.isAnswered(.sexualArrangement)
        case .religion:
            return true // The only optional question; both skips have matching defaults.
        case .languages:
            return !state.languages.isEmpty
        case .location:
            return state.location != nil
        case .hasChildren:
            return state.lifestyle.hasChildren != nil
        case .partnerHasChildren:
            return state.lifestyle.openToPartnerWithChildren != nil
        case .futureChildren:
            return state.lifestyle.futureChildren != nil
        case .alcohol, .smoking, .drugs:
            guard let substance = step.substance else { return false }
            let answer = state.lifestyle[substance]
            return answer.ownLevel != nil && answer.partnerMaximumLevel != nil
        case .aloneTime:
            return state.lifestyle.aloneTime.isComplete
        }
    }

    var isCompleted: Bool { state.completedAt != nil && !state.isUnderageLocked }

    /// Evaluated after a deliberate answer selection, never on entering a page.
    var shouldAutoAdvanceAfterAnswerSelection: Bool {
        guard editingStep == nil, !state.isUnderageLocked else { return false }
        switch currentStep {
        case .gender, .hasChildren, .partnerHasChildren, .futureChildren:
            return isComplete(currentStep)
        case .partnerGenders:
            return GenderIdentity.onboardingOptions.allSatisfy { state.partnerGenders.contains($0) }
        case .sexualArrangement:
            return state.relationshipPreferences.shouldAutoAdvance(.sexualArrangement)
        case .aloneTime:
            return state.lifestyle.aloneTime.hasCustomValuesForAutoAdvance
        default:
            return false
        }
    }

    // MARK: - Navigation

    @discardableResult
    func submitCurrentStep() -> ProfileCreationSubmission {
        if let missingSubstanceSide {
            substanceMode = missingSubstanceSide
            return .advanced
        }
        if currentStep == .religion {
            if state.religionPhase == .own {
                setReligionPhase(.partner)
                return .advanced
            }
            state.religion.acceptedPartnerReligions = state.religion.effectivePartnerReligions
        }
        if state.currentStep == .dateOfBirth {
            let result = submitBirthDate()
            guard result == .advanced, editingStep != nil else { return result }
            return finishEditing()
        }
        guard isComplete(state.currentStep) else {
            reject(nil)
            return .rejected
        }
        if editingStep != nil {
            return finishEditing()
        }
        if let next = state.currentStep.next {
            move(to: next)
            return .advanced
        }
        return complete() ? .completed : .rejected
    }

    /// Returns `false` on the first step, where the caller leaves onboarding.
    @discardableResult
    func goBack() -> Bool {
        feedback = nil
        if currentStep == .religion, state.religionPhase == .partner {
            setReligionPhase(.own)
            return true
        }
        guard let previous = state.currentStep.previous else { return false }
        move(to: previous)
        return true
    }

    /// An unsaved change is never stored; a relaunch keeps the saved answers.
    func persist() {
        store.save(stateBeforeEditing ?? state)
    }

    private func move(to step: ProfileCreationStep) {
        feedback = nil
        if step == .religion { state.religionPhase = .own }
        state.currentStep = step
        substanceMode = missingSubstanceSide ?? .own
        persist()
    }

    private func reject(_ feedback: ProfileCreationFeedback?) {
        self.feedback = feedback
        rejectionCount += 1
    }

    // MARK: - Date of birth

    var birthDateSelection: CalendarDate { state.birthDateSelection }

    var birthDateChangedFields: Set<BirthDateField> {
        BirthDateRules.changedFields(state.birthDateSelection, from: state.birthDateBaseline)
    }

    var birthDateEvaluation: BirthDateEvaluation {
        BirthDateRules.evaluate(state.birthDateSelection, today: today, calendar: calendar)
    }

    /// The live age is hidden until the user has moved at least one field.
    var visibleAge: Int? {
        guard !birthDateChangedFields.isEmpty else { return nil }
        return birthDateEvaluation.age
    }

    /// A live hint for selections that can never be accepted.
    var birthDateHint: ProfileCreationFeedback? {
        guard !birthDateChangedFields.isEmpty else { return nil }
        switch birthDateEvaluation {
        case .nonexistent(let days):
            return .nonexistentDate(
                monthName: monthName(state.birthDateSelection.month),
                year: state.birthDateSelection.year,
                days: days
            )
        case .future:
            return .futureDate
        default:
            return nil
        }
    }

    /// Automatic progression only applies once all three fields were changed,
    /// and only once per accepted selection.
    var shouldAutoAdvanceFromBirthDate: Bool {
        guard state.currentStep == .dateOfBirth,
              editingStep == nil,
              !state.isUnderageLocked,
              birthDateChangedFields.count == BirthDateField.allCases.count,
              state.birthDateSelection != state.dateOfBirth,
              case .adult = birthDateEvaluation else { return false }
        return true
    }

    func updateBirthDate(_ selection: CalendarDate) {
        guard selection != state.birthDateSelection else { return }
        state.birthDateSelection = selection
        feedback = nil
    }

    func monthName(_ month: Int) -> String {
        var displayCalendar = calendar
        displayCalendar.locale = AppLocale.current
        let symbols = displayCalendar.monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
    }

    private func submitBirthDate() -> ProfileCreationSubmission {
        switch birthDateEvaluation {
        case .today:
            reject(.birthday)
            return .rejected
        case .nonexistent, .future:
            reject(birthDateHint ?? .futureDate)
            return .rejected
        case .minor:
            lockForUnderage()
            return .underage
        case .adult(let age):
            state.dateOfBirth = state.birthDateSelection
            if state.partnerAgeRange?.isCustomized != true {
                state.partnerAgeRange = PartnerAgeRules.suggestedRange(forAge: age)
            }
            if editingStep == nil { move(to: .partnerAgeRange) }
            return .advanced
        }
    }

    // MARK: - Underage lock

    /// Every answer is discarded; nothing a minor entered is kept.
    private func lockForUnderage() {
        editingStep = nil
        stateBeforeEditing = nil
        var locked = ProfileCreationState(today: today, applicationLanguage: AppLocale.languageCode)
        locked.birthDateSelection = state.birthDateSelection
        locked.isUnderageLocked = true
        state = locked
        feedback = nil
        persist()
    }

    /// Only restarts input. Age is validated again on the reopened step.
    func restartAfterUnderageLock() {
        let today = today
        state.isUnderageLocked = false
        state.dateOfBirth = nil
        state.birthDateBaseline = today
        state.birthDateSelection = today
        state.currentStep = .dateOfBirth
        feedback = nil
        persist()
    }

    // MARK: - Answers

    var partnerAgeRange: PartnerAgeRange {
        state.partnerAgeRange ?? PartnerAgeRules.suggestedRange(forAge: state.age(on: today) ?? 25)
    }

    func updatePartnerAgeRange(minimum: Int, maximum: Int) {
        let clamped = PartnerAgeRules.clamped(minimum: minimum, maximum: maximum)
        let range = PartnerAgeRange(minimum: clamped.minimum, maximum: clamped.maximum, isCustomized: true)
        guard range.minimum != state.partnerAgeRange?.minimum || range.maximum != state.partnerAgeRange?.maximum else { return }
        state.partnerAgeRange = range
    }

    func updatePartnerHeightRange(minimum: Int, maximum: Int) {
        let range = PartnerHeightRules.clamped(minimum: minimum, maximum: maximum)
        guard range != state.partnerHeightRange else { return }
        state.partnerHeightRange = range
    }

    func updateHeight(_ centimeters: Int) {
        let value = HeightRules.clamped(centimeters)
        guard value != state.heightCentimeters else { return }
        state.heightCentimeters = value
        if value != HeightRules.defaultCentimeters {
            state.hasAdjustedHeight = true
        }
    }

    func selectGender(_ gender: GenderIdentity) {
        state.gender = gender
    }

    func togglePartnerGender(_ gender: GenderIdentity) {
        if state.partnerGenders.contains(gender) {
            state.partnerGenders.remove(gender)
        } else {
            state.partnerGenders.insert(gender)
        }
    }

    func selectPreference(_ optionID: String, in question: RelationshipPreferenceQuestion) {
        state.relationshipPreferences.select(optionID, in: question)
    }

    func toggleOwnReligion(_ religion: Religion) {
        state.religion.own = state.religion.own == religion ? nil : religion
    }

    /// A new choice opens the partner side; clearing a choice keeps this side open.
    func selectOwnReligion(_ religion: Religion) {
        toggleOwnReligion(religion)
        if state.religion.own != nil { setReligionPhase(.partner) }
    }

    func togglePartnerReligion(_ religion: Religion) {
        if state.religion.acceptedPartnerReligions.contains(religion) {
            state.religion.acceptedPartnerReligions.remove(religion)
        } else {
            state.religion.acceptedPartnerReligions.insert(religion)
        }
    }

    func setReligionPhase(_ phase: ReligionQuestionPhase) {
        state.religionPhase = phase
        persist()
    }

    @discardableResult
    func skipReligionPhase() -> ProfileCreationSubmission {
        guard currentStep == .religion else { return .rejected }
        switch state.religionPhase {
        case .own: state.religion.own = nil
        case .partner: state.religion.acceptedPartnerReligions = Set(Religion.allCases)
        }
        return submitCurrentStep()
    }

    func addLanguage(_ code: String) {
        guard !state.languages.contains(code) else { return }
        state.languages.append(code)
    }

    func replaceLanguage(_ existing: String, with code: String) {
        guard existing != code,
              !state.languages.contains(code),
              let index = state.languages.firstIndex(of: existing) else { return }
        state.languages[index] = code
    }

    func removeLanguage(_ code: String) {
        guard state.languages.count > 1 else { return }
        state.languages.removeAll { $0 == code }
    }

    func selectLocation(_ coordinate: CLLocationCoordinate2D, source: SelectedLocation.Source) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        state.location = SelectedLocation(coordinate: coordinate, source: source)
    }

    func updatePlaceName(_ name: String?, for coordinate: CLLocationCoordinate2D) {
        guard let location = state.location,
              location.latitude == coordinate.latitude,
              location.longitude == coordinate.longitude else { return }
        state.location?.placeName = name
    }

    func updateSearchRadius(_ kilometers: Int) {
        let value = SearchRadiusRules.clamped(kilometers)
        guard value != state.searchRadiusKilometers else { return }
        state.searchRadiusKilometers = value
    }

    func setHasChildren(_ value: Bool) {
        state.lifestyle.hasChildren = value
    }

    func setOpenToPartnerWithChildren(_ value: Bool) {
        state.lifestyle.openToPartnerWithChildren = value
    }

    func setFutureChildren(_ wish: FutureChildrenWish) {
        state.lifestyle.futureChildren = wish
    }

    func setOwnLevel(_ level: Int, for substance: Substance) {
        guard substance.levels.indices.contains(level) else { return }
        state.lifestyle[substance].ownLevel = level
    }

    func setPartnerMaximumLevel(_ level: Int, for substance: Substance) {
        guard substance.levels.indices.contains(level) else { return }
        state.lifestyle[substance].partnerMaximumLevel = level
    }

    /// The partner value follows the user's own answer until it is changed.
    func setAloneTimeOwn(_ value: Int) {
        guard CompatibilityScaleAnswer.range.contains(value) else { return }
        state.lifestyle.aloneTime.own = value
        if !state.lifestyle.aloneTime.isPartnerCustomized {
            state.lifestyle.aloneTime.partner = value
        }
    }

    func setAloneTimePartner(_ value: Int) {
        guard CompatibilityScaleAnswer.range.contains(value) else { return }
        state.lifestyle.aloneTime.partner = value
        state.lifestyle.aloneTime.isPartnerCustomized = true
    }

    func setAloneTimeImportance(_ value: Int) {
        guard CompatibilityScaleAnswer.range.contains(value) else { return }
        state.lifestyle.aloneTime.importance = value
    }

    // MARK: - Completion

    /// Opens one answer of a completed profile. Saving validates it, the
    /// birthday included, and writes the whole profile again.
    func beginEditing(_ step: ProfileCreationStep) {
        guard isCompleted else { return }
        stateBeforeEditing = state
        editingStep = step
        state.birthDateBaseline = today
        state.birthDateSelection = state.dateOfBirth ?? today
        feedback = nil
        state.currentStep = step
        substanceMode = missingSubstanceSide ?? .own
        if step == .religion { state.religionPhase = .own }
    }

    /// Discards the change and keeps the saved answers.
    func cancelEditing() {
        guard let saved = stateBeforeEditing else { return }
        state = saved
        stateBeforeEditing = nil
        editingStep = nil
        feedback = nil
    }

    private func finishEditing() -> ProfileCreationSubmission {
        let saved = stateBeforeEditing
        stateBeforeEditing = nil
        editingStep = nil
        guard complete() else {
            stateBeforeEditing = saved
            editingStep = state.currentStep
            return .rejected
        }
        return .completed
    }

    private func complete() -> Bool {
        guard let birth = state.dateOfBirth,
              let birthDate = birth.date(in: calendar),
              BirthDateRules.age(of: birth, on: today) >= BirthDateRules.minimumAge else {
            move(to: .dateOfBirth)
            reject(nil)
            return false
        }
        if let incomplete = ProfileCreationStep.allCases.first(where: { !isComplete($0) }) {
            move(to: incomplete)
            reject(nil)
            return false
        }

        let completedAt = now()
        var draft = ((try? repository?.loadProfile()) ?? nil) ?? ProfileDraft()
        draft.applyProfileCreation(state, birthDate: birthDate, completedAt: completedAt)
        do {
            try repository?.saveProfile(draft)
        } catch {
            reject(.saveFailed(error.localizedDescription))
            return false
        }
        state.completedAt = completedAt
        persist()
        return true
    }
}


// MARK: - Auto matching

extension ProfileCreationViewModel {
    var dealbreakers: MatchDealbreakers { MatchDealbreakers(state: state) }

    var canResumeAutoMatching: Bool {
        isCompleted && state.autoMatching.hasCompletedSetup && state.autoMatching.isReady
    }

    @discardableResult
    func resumeAutoMatching() -> Bool {
        guard canResumeAutoMatching else { return false }
        return joinAutoMatching()
    }

    /// The photo chosen for auto matching, read from the saved profile.
    var autoMatchingPhoto: Data? {
        autoMatchingReferencePhoto?.imageData
    }

    var autoMatchingReferencePhoto: ProfilePhoto? {
        guard let id = state.autoMatching.photoID,
              let draft = (try? repository?.loadProfile()) ?? nil else { return nil }
        return draft.photos.first { $0.id == id }
    }

    var hasVerifiedAutoMatchingPhoto: Bool {
        guard let photo = autoMatchingReferencePhoto, let receipt = autoMatchingPhotoVerification else { return false }
        return receipt.outcome == .match && receipt.belongs(to: photo.id, imageData: photo.imageData)
    }

    func recordAutoMatchingPhotoVerification(_ receipt: PhotoVerificationReceipt) {
        guard let photo = autoMatchingReferencePhoto,
              receipt.belongs(to: photo.id, imageData: photo.imageData) else { return }
        autoMatchingPhotoVerification = receipt
    }

    /// Compresses the photo and stores it with the profile, replacing the
    /// previous auto-matching photo. Returns a message when that fails.
    func setAutoMatchingPhoto(_ data: Data) -> String? {
        guard let repository else { return L10n("Photos can’t be saved on this device.") }
        do {
            let processed = try ImageProcessingService().process(data)
            var draft = try repository.loadProfile() ?? ProfileDraft()
            if let previous = state.autoMatching.photoID {
                draft.photos.removeAll { $0.id == previous }
            }
            let photo = ProfilePhoto(imageData: processed, order: draft.photos.count)
            draft.photos.append(photo)
            draft.normalizePhotoOrder()
            // A replaced reference cannot keep auto matching enabled with a stale verification.
            draft.autoMatching = state.autoMatching
            draft.autoMatching.photoID = photo.id
            draft.autoMatching.isEnabled = false
            draft.autoMatching.hasCompletedSetup = false
            try repository.saveProfile(draft)
            state.autoMatching.photoID = photo.id
            state.autoMatching.isEnabled = false
            state.autoMatching.hasCompletedSetup = false
            autoMatchingPhotoVerification = nil
            persist()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func setOwnAttractiveness(_ value: Int) {
        guard AppearanceRating.range.contains(value) else { return }
        state.autoMatching.ownAttractiveness = value
    }

    func setPartnerMinimumAttractiveness(_ value: Int) {
        guard AppearanceRating.range.contains(value) else { return }
        state.autoMatching.partnerMinimumAttractiveness = value
    }

    func setMinimumMatchPercent(_ percent: Int) {
        state.autoMatching.minimumMatchPercent = AutoMatchingSettings.clampedScore(percent)
    }

    func setRequiresVerifiedPartnerPhoto(_ required: Bool) {
        state.autoMatching.requiresVerifiedPartnerPhoto = required
    }

    /// Removes only the auto-matching reference; other profile photos remain.
    func removeAutoMatchingPhoto() -> String? {
        guard let repository else { return L10n("Photos can’t be saved on this device.") }
        do {
            var draft = try repository.loadProfile() ?? ProfileDraft()
            if let id = state.autoMatching.photoID {
                draft.photos.removeAll { $0.id == id }
            }
            draft.normalizePhotoOrder()
            var settings = state.autoMatching
            settings.photoID = nil
            draft.autoMatching = settings
            try repository.saveProfile(draft)
            state.autoMatching = settings
            autoMatchingPhotoVerification = nil
            persist()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Both scores are required. Joining without a photo is allowed; a chosen
    /// photo must pass verification. The partner requirement is independent.
    @discardableResult
    func joinAutoMatching() -> Bool {
        guard isCompleted, state.autoMatching.isReady,
              state.autoMatching.photoID == nil || state.autoMatching.hasCompletedSetup || hasVerifiedAutoMatchingPhoto else { return false }
        let hadCompletedSetup = state.autoMatching.hasCompletedSetup
        state.autoMatching.isEnabled = true
        state.autoMatching.hasCompletedSetup = true
        guard saveAutoMatching() else {
            state.autoMatching.hasCompletedSetup = hadCompletedSetup
            return false
        }
        return true
    }

    func leaveAutoMatching() {
        state.autoMatching.isEnabled = false
        saveAutoMatching()
    }

    @discardableResult
    private func saveAutoMatching() -> Bool {
        if let repository {
            do {
                var draft = try repository.loadProfile() ?? ProfileDraft()
                draft.autoMatching = state.autoMatching
                try repository.saveProfile(draft)
            } catch {
                state.autoMatching.isEnabled = false
                return false
            }
        }
        persist()
        return true
    }
}

extension ProfileDraft {
    mutating func applyProfileCreation(_ state: ProfileCreationState, birthDate: Date, completedAt: Date) {
        dateOfBirth = birthDate
        heightCentimeters = state.heightCentimeters
        preferredPartnerMinimumAge = state.partnerAgeRange?.minimum
        preferredPartnerMaximumAge = state.partnerAgeRange?.maximum
        gender = state.gender
        selfDescribedGender = ""
        interestedIn = state.partnerGenders
        let height = state.partnerHeightRange
        preferredPartnerMinimumHeight = height.isAny ? nil : height.minimum
        preferredPartnerMaximumHeight = height.isAny ? nil : height.maximum
        autoMatching = state.autoMatching
        relationshipPreferences = state.relationshipPreferences
        religion = state.religion
        languages = state.languages
        lifestyle = state.lifestyle
        preferredRadiusKilometers = state.searchRadiusKilometers
        matchLocation = state.location.map {
            MatchLocation(coordinate: $0.coordinate, radiusKilometers: state.searchRadiusKilometers)
        }
        profileCreationCompletedAt = completedAt
    }
}
