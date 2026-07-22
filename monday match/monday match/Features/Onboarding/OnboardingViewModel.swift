import Foundation
import CoreLocation

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

    var canContinue: Bool {
        switch currentStep {
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
            validationMessage = messageForCurrentStep()
            return
        }

        guard let nextStep = currentStep.next else { return }
        currentStep = nextStep
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

    func addPhotoData(
        _ dataItems: [Data],
        processor: ImageProcessingService = ImageProcessingService()
    ) {
        photoErrorMessage = nil

        let remainingCapacity = maximumPhotos - draft.photos.count
        guard remainingCapacity > 0 else { return }

        for data in dataItems.prefix(remainingCapacity) {
            do {
                let processed = try processor.process(data)
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

    private func messageForCurrentStep() -> String {
        switch currentStep {
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
