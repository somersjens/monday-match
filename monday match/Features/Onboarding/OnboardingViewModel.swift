import Combine
import Foundation
import SwiftUI // for Array.move(fromOffsets:toOffset:)

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .relationshipType
    @Published var draft = ProfileDraft()
    @Published var validationMessage: String?
    @Published var photoErrorMessage: String?

    let minimumAge = BirthDateRules.minimumAge
    let minimumPhotos = 1
    let maximumPhotos = 3

    private let imageProcessor: ImageProcessingService
    private let repository: ProfileRepository?

    init(
        repository: ProfileRepository? = nil,
        imageProcessor: ImageProcessingService? = nil
    ) {
        self.repository = repository
        // Built here (not as a default argument) because the initializer is
        // MainActor-isolated, while default arguments are evaluated nonisolated.
        self.imageProcessor = imageProcessor ?? ImageProcessingService()

        reloadDraft()
    }

    /// Resumes a half-finished onboarding instead of starting from scratch,
    /// and picks up answers saved by profile creation.
    func reloadDraft() {
        if let repository, let stored = try? repository.loadProfile() {
            draft = stored
        }
    }

    /// Profile creation, including its age check, must be complete first.
    var requiresProfileCreation: Bool {
        !draft.hasCompletedProfileCreation
    }

    /// Whether the stored draft already passes every check `finishOnboarding`
    /// enforces, e.g. a profile built before the account was created.
    var isReadyToComplete: Bool {
        draft.isAtLeast(age: minimumAge)
            && draft.hasCompletedProfileCreation
            && OnboardingStep.allCases.allSatisfy(isComplete(step:))
    }

    var canContinue: Bool {
        isComplete(step: currentStep)
    }

    private func isComplete(step: OnboardingStep) -> Bool {
        switch step {
        case .relationshipType:
            return !draft.relationshipTypes.isEmpty

        case .profileBasics:
            let name = draft.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bio = draft.bio
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return name.count >= 2 && bio.count >= 20

        case .interests:
            return draft.interests.count >= 3

        case .compatibility:
            return draft.compatibilityAnswers[
                CompatibilityQuestion.likesChicken.id
            ] != nil

        case .photos:
            return draft.photos.count >= minimumPhotos

        case .review:
            return true
        }
    }

    func continueToNextStep() {
        validationMessage = nil

        guard canContinue else {
            validationMessage = message(for: currentStep)
            return
        }

        guard let nextStep = currentStep.next else { return }
        currentStep = nextStep
        persistDraft()
    }

    /// Final check before leaving onboarding. Every earlier step is re-validated,
    /// because a user can navigate back and clear a required field.
    /// Returns `false` and jumps to the offending step when something is missing.
    @discardableResult
    func finishOnboarding() -> Bool {
        validationMessage = nil

        // Enforced here as well as in profile creation, so no client-side
        // path can finish onboarding with a missing or underage birth date.
        guard draft.isAtLeast(age: minimumAge), draft.hasCompletedProfileCreation else {
            validationMessage = "You must be at least \(minimumAge) years old."
            return false
        }

        for step in OnboardingStep.allCases where !isComplete(step: step) {
            currentStep = step
            validationMessage = message(for: step)
            return false
        }

        persistDraft()
        return true
    }

    private func persistDraft() {
        try? repository?.saveProfile(draft)
    }

    func goBack() {
        validationMessage = nil
        photoErrorMessage = nil

        guard let previousStep = currentStep.previous else { return }
        currentStep = previousStep
    }

    func toggleRelationshipType(_ type: RelationshipType) {
        if draft.relationshipTypes.contains(type) {
            draft.relationshipTypes.remove(type)
        } else {
            draft.relationshipTypes.insert(type)
        }
    }

    func toggleProfileInterest(_ interest: ProfileInterest) {
        if draft.interests.contains(interest) {
            draft.interests.remove(interest)
        } else {
            draft.interests.insert(interest)
        }
    }

    func updateCompatibilityAnswer(
        _ answer: CompatibilityAnswer
    ) {
        draft.compatibilityAnswers[answer.questionID] = answer
    }

    // NOTE: no defaulted second parameter here. A method with default arguments
    // cannot be passed directly as a `([Data]) -> Void` closure.
    func addPhotoData(_ dataItems: [Data]) {
        photoErrorMessage = nil

        let remainingCapacity = maximumPhotos - draft.photos.count
        guard remainingCapacity > 0 else {
            photoErrorMessage = "You can add at most \(maximumPhotos) photos."
            return
        }

        for data in dataItems.prefix(remainingCapacity) {
            do {
                let processed = try imageProcessor.process(data)
                let photo = ProfilePhoto(
                    imageData: processed,
                    order: draft.photos.count
                )
                draft.photos.append(photo)
            } catch {
                photoErrorMessage = error.localizedDescription
            }
        }

        draft.normalizePhotoOrder()
    }

    func removePhoto(id: UUID) {
        draft.photos.removeAll { $0.id == id }
        draft.normalizePhotoOrder()
    }

    func movePhoto(from source: IndexSet, to destination: Int) {
        draft.photos.move(
            fromOffsets: source,
            toOffset: destination
        )
        draft.normalizePhotoOrder()
    }

    private func message(for step: OnboardingStep) -> String {
        switch step {
        case .relationshipType:
            return "Choose at least one relationship type."
        case .profileBasics:
            return "Add a display name and a bio of at least 20 characters."
        case .interests:
            return "Choose at least three interests."
        case .compatibility:
            return "Complete the compatibility question."
        case .photos:
            return "Add at least one profile photo."
        case .review:
            return ""
        }
    }
}
