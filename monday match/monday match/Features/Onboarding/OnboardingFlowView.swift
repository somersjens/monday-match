import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var locationService = LocationService()

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OnboardingProgressHeader(
                    title: viewModel.currentStep.title,
                    progress: viewModel.currentStep.progress,
                    showsBackButton: viewModel.currentStep.previous != nil,
                    onBack: viewModel.goBack
                )

                Group {
                    switch viewModel.currentStep {
                    case .dateOfBirth:
                        DateOfBirthStepView(draft: $viewModel.draft)

                    case .gender:
                        GenderStepView(draft: $viewModel.draft)

                    case .lookingFor:
                        LookingForStepView(
                            selectedGenders: viewModel.draft.interestedIn,
                            onToggle: viewModel.toggleInterest
                        )

                    case .relationshipType:
                        RelationshipTypeStepView(
                            selectedTypes: viewModel.draft.relationshipTypes,
                            onToggle: viewModel.toggleRelationshipType
                        )

                    case .location:
                        LocationStepView(
                            location: viewModel.draft.matchLocation,
                            locationService: locationService,
                            errorMessage: viewModel.locationErrorMessage,
                            onLocationReceived: viewModel.setLocation,
                            onError: {
                                viewModel.locationErrorMessage = $0
                            }
                        )

                    case .distance:
                        DistanceStepView(
                            radiusKilometers: viewModel.draft.preferredRadiusKilometers,
                            onRadiusChanged: viewModel.updateRadius
                        )

                    case .profileBasics:
                        ProfileBasicsStepView(
                            draft: $viewModel.draft
                        )

                    case .interests:
                        InterestsStepView(
                            selectedInterests: viewModel.draft.interests,
                            onToggle: viewModel.toggleProfileInterest
                        )

                    case .compatibility:
                        CompatibilityQuestionStepView(
                            question: .likesChicken,
                            answer: viewModel.draft.compatibilityAnswer(
                                for: .likesChicken
                            ),
                            onAnswerChanged: viewModel.updateCompatibilityAnswer
                        )

                    case .photos:
                        PhotoSelectionStepView(
                            photos: viewModel.draft.photos,
                            maximumPhotos: viewModel.maximumPhotos,
                            errorMessage: viewModel.photoErrorMessage,
                            onAddPhotoData: viewModel.addPhotoData,
                            onRemovePhoto: viewModel.removePhoto,
                            onMovePhoto: viewModel.movePhoto
                        )

                    case .review:
                        ProfilePreviewStepView(
                            draft: viewModel.draft
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingBottomBar(
                    buttonTitle: viewModel.currentStep == .review
                        ? "Complete profile"
                        : "Next",
                    validationMessage: viewModel.validationMessage,
                    isEnabled: viewModel.canContinue,
                    action: {
                        if viewModel.currentStep == .review {
                            onComplete()
                        } else {
                            viewModel.continueToNextStep()
                        }
                    }
                )
            }
            .background(AppColors.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
