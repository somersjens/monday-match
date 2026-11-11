import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var viewModel: OnboardingViewModel

    private let repository: ProfileRepository?
    private let profileCreationStore: ProfileCreationStateStoring
    /// Receives the completed draft so the caller can persist it.
    let onComplete: (ProfileDraft) -> Void
    /// Called when profile creation finds the user is underage.
    let onUnderage: () -> Void

    init(
        repository: ProfileRepository? = nil,
        profileCreationStore: ProfileCreationStateStoring? = nil,
        onComplete: @escaping (ProfileDraft) -> Void,
        onUnderage: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.profileCreationStore = profileCreationStore ?? InMemoryProfileCreationStore()
        self.onComplete = onComplete
        self.onUnderage = onUnderage
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(repository: repository)
        )
    }

    var body: some View {
        if viewModel.requiresProfileCreation {
            // Accounts that skipped profile creation (e.g. a sign-in from a
            // fresh install) complete it before anything else.
            ProfileCreationGateView(
                store: profileCreationStore,
                repository: repository,
                onComplete: viewModel.reloadDraft,
                onUnderage: onUnderage
            )
        } else {
            profileDetails
        }
    }

    private var profileDetails: some View {
        NavigationStack { profileSteps }
    }

    private var profileSteps: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(
                title: viewModel.currentStep.title,
                progress: viewModel.currentStep.progress,
                showsBackButton: viewModel.currentStep.previous != nil,
                onBack: viewModel.goBack
            )

            Group {
                switch viewModel.currentStep {
                case .relationshipType:
                    RelationshipTypeStepView(
                        selectedTypes: viewModel.draft.relationshipTypes,
                        onToggle: viewModel.toggleRelationshipType
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
                // The button stays tappable so `continueToNextStep()` can
                // explain *why* the step is incomplete. Disabling it here
                // made the validation message unreachable.
                isEnabled: true,
                action: {
                    guard viewModel.currentStep == .review else {
                        viewModel.continueToNextStep()
                        return
                    }

                    guard viewModel.finishOnboarding() else { return }
                    onComplete(viewModel.draft)
                }
            )
        }
        .background(AppColors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    OnboardingFlowView(
        repository: InMemoryProfileRepository(),
        onComplete: { _ in }
    )
}
