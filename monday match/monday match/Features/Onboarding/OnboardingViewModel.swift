import Combine
import CoreLocation
import Foundation
import SwiftUI // for Array.move(fromOffsets:toOffset:)

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .dateOfBirth
    @Published var draft = ProfileDraft()
    @Published var validationMessage: String?
    @Published var locationErrorMessage: String?
    @Published var photoErrorMessage: String?

    let minimumAge = 18
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

        // Resume a half-finished onboarding instead of starting from scratch.
        if let repository, let stored = try? repository.loadProfile() {
            draft = stored
        }
    }

    var canContinue: Bool {
        isComplete(step: currentStep)
    }

    private func isComplete(step: OnboardingStep) -> Bool {
        switch step {
        case .dateOfBirth:
            return draft.isAtLeast(age: minimumAge)

        case .gender:
            guard let gender = draft.gender else { return false }

            if gender == .selfDescribed {
                return !draft.selfDescribedGender
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            }

            return true

        case .lookingFor:
            return !draft.interestedIn.isEmpty

        case .relationshipType:
            return !draft.relationshipTypes.isEmpty

        case .location:
            return draft.matchLocation != nil

        case .distance:
            return (5...250).contains(draft.preferredRadiusKilometers)

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
        locationErrorMessage = nil
        photoErrorMessage = nil

        guard let previousStep = currentStep.previous else { return }
        currentStep = previousStep
    }

    func toggleInterest(_ gender: GenderIdentity) {
        if draft.interestedIn.contains(gender) {
            draft.interestedIn.remove(gender)
        } else {
            draft.interestedIn.insert(gender)
        }
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

    func setLocation(_ location: CLLocation) {
        draft.matchLocation = MatchLocation(
            coordinate: location.coordinate,
            radiusKilometers: draft.preferredRadiusKilometers
        )
        locationErrorMessage = nil
    }

    func updateRadius(_ radius: Int) {
        draft.preferredRadiusKilometers = radius

        guard let existingLocation = draft.matchLocation else { return }

        draft.matchLocation = MatchLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: existingLocation.latitude,
                longitude: existingLocation.longitude
            ),
            radiusKilometers: radius,
            updatedAt: existingLocation.updatedAt
        )
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
        case .dateOfBirth:
            return "You must be at least \(minimumAge) years old."
        case .gender:
            return "Choose your gender before continuing."
        case .lookingFor:
            return "Choose at least one gender you are interested in."
        case .relationshipType:
            return "Choose at least one relationship type."
        case .location:
            return "Add your current location before continuing."
        case .distance:
            return "Choose a matching distance between 5 and 250 km."
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
