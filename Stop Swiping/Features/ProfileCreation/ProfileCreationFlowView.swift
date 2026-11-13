import SwiftUI

/// The step container: progress, the animated step, and Continue / Back. It
/// is transparent so it can sit directly on the landing page's light.
struct ProfileCreationFlowView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService
    /// The first step can return to the landing page when one is behind it.
    let canExitFromFirstStep: Bool
    let onExit: () -> Void
    let onUnderage: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedStep: ProfileCreationStep
    @State private var direction: StepDirection = .forward
    @State private var isNavigating = false
    @State private var navigationToken = 0
    @State private var hasEntered = false
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(
        viewModel: ProfileCreationViewModel,
        locationService: LocationService,
        canExitFromFirstStep: Bool,
        onExit: @escaping () -> Void,
        onUnderage: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.locationService = locationService
        self.canExitFromFirstStep = canExitFromFirstStep
        self.onExit = onExit
        self.onUnderage = onUnderage
        self.onComplete = onComplete
        _displayedStep = State(initialValue: viewModel.currentStep)
    }

    private var isEditing: Bool { viewModel.editingStep != nil }

    private var showsBack: Bool {
        isEditing || displayedStep.previous != nil || canExitFromFirstStep
    }

    private var primaryTitle: String {
        if displayedStep == .religion {
            if viewModel.state.religionPhase == .partner { return L10n("Save") }
            return viewModel.state.religion.own == nil ? L10n("Skip") : L10n("Continue")
        }
        if isEditing { return L10n("Save") }
        return displayedStep.next == nil ? L10n("Complete") : L10n("Continue")
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressDots(current: displayedStep.number, total: ProfileCreationStep.allCases.count)
                .padding(.top, 2)
                .opacity(hasEntered ? 1 : 0)

            ZStack(alignment: .top) {
                stepPage(displayedStep)
                    .allowsHitTesting(!isNavigating)
                    .id(displayedStep)
                    .transition(.onboardingStep(direction, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered || reduceMotion ? 0 : 28)
            .blur(radius: hasEntered || reduceMotion ? 0 : 10)

            bottomBar
        }
        .onAppear {
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : 0.12)) {
                hasEntered = true
            }
        }
        .onChange(of: viewModel.currentStep) { _, step in
            show(step)
        }
        .onChange(of: viewModel.rejectionCount) {
            if let feedback = viewModel.feedback {
                AccessibilityNotification.Announcement(feedback.message).post()
            }
        }
        .onChange(of: viewModel.state.religionPhase) {
            isTitleFocused = true
        }
        .sensoryFeedback(.warning, trigger: viewModel.rejectionCount)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: displayedStep)
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepPage(_ step: ProfileCreationStep) -> some View {
        if step == .location {
            // The map handles its own gestures, so this page never scrolls.
            VStack(alignment: .leading, spacing: 20) {
                OnboardingStepHeader(title: step.title, subtitle: step.subtitle, titleFocus: $isTitleFocused)
                LocationStep(viewModel: viewModel, locationService: locationService)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: OnboardingTheme.contentWidth)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    OnboardingStepHeader(
                        title: step == .religion ? viewModel.state.religionPhase.title : step.title,
                        subtitle: step == .religion ? viewModel.state.religionPhase.subtitle : step.subtitle,
                        titleFocus: $isTitleFocused
                    )
                    stepContent(step)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // Each part starts at its question, even if the previous list
            // was scrolled down to the last option.
            .id(step == .religion ? viewModel.state.religionPhase : .own)
        }
    }

    @ViewBuilder
    private func stepContent(_ step: ProfileCreationStep) -> some View {
        switch step {
        case .dateOfBirth:
            DateOfBirthStep(viewModel: viewModel, onAutoAdvance: advanceAutomatically)
        case .partnerAgeRange:
            PartnerAgeRangeStep(viewModel: viewModel)
        case .height:
            HeightStep(viewModel: viewModel)
        case .partnerHeightRange:
            PartnerHeightRangeStep(viewModel: viewModel)
        case .gender:
            GenderStep(viewModel: viewModel, onAnswerSelected: advanceAfterAnswerSelection)
        case .partnerGenders:
            PartnerGendersStep(viewModel: viewModel, onAnswerSelected: advanceAfterAnswerSelection)
        case .sexualArrangement:
            PreferenceQuestionStep(viewModel: viewModel, question: .sexualArrangement, onAnswerSelected: advanceAfterAnswerSelection)
        case .religion:
            ReligionStep(viewModel: viewModel)
        case .languages:
            LanguagesStep(viewModel: viewModel)
        case .location:
            EmptyView()
        case .hasChildren, .partnerHasChildren, .futureChildren:
            ChildrenStep(viewModel: viewModel, step: step, onAnswerSelected: advanceAfterAnswerSelection)
        case .alcohol, .smoking, .drugs:
            if let substance = step.substance {
                SubstanceStep(viewModel: viewModel, substance: substance)
            }
        case .aloneTime:
            CompatibilityScaleStep(viewModel: viewModel, question: .aloneTime, onAnswerSelected: advanceAfterAnswerSelection)
        }
    }

    // MARK: - Controls

    /// Sits exactly where the landing page's buttons are, so Get started
    /// becomes Continue and the account link becomes Back.
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if case .saveFailed = viewModel.feedback, let feedback = viewModel.feedback {
                OnboardingFeedbackLabel(feedback: feedback)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }

            Button(action: handleContinue) {
                Text(primaryTitle)
                    .contentTransition(.opacity)
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!viewModel.canContinue)

            HStack(spacing: 12) {
                Button(isEditing || (displayedStep == .religion && viewModel.state.religionPhase == .partner) ? L10n("Cancel") : L10n("Back"), action: handleBack)
                    .buttonStyle(QuietButtonStyle())
                    .opacity(showsBack ? 1 : 0)
                    .disabled(!showsBack)
                    .accessibilityHidden(!showsBack)
            }
        }
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .opacity(hasEntered ? 1 : 0)
    }

    // MARK: - Navigation

    private func handleContinue() {
        guard !isNavigating else { return }
        handleSubmission(viewModel.submitCurrentStep())
    }

    private func handleSubmission(_ submission: ProfileCreationSubmission) {
        switch submission {
        case .advanced:
            isNavigating = viewModel.currentStep != displayedStep
        case .rejected:
            break
        case .underage:
            isNavigating = true
            onUnderage()
        case .completed:
            isNavigating = true
            onComplete()
        }
    }

    private func handleBack() {
        guard !isNavigating else { return }
        if isEditing {
            isNavigating = true
            viewModel.cancelEditing()
            onExit()
        } else if viewModel.goBack() {
            isNavigating = viewModel.currentStep != displayedStep
        } else if canExitFromFirstStep {
            isNavigating = true
            onExit()
        }
    }

    private func advanceAutomatically() {
        guard !isNavigating, viewModel.shouldAutoAdvanceFromBirthDate else { return }
        handleContinue()
    }

    private func advanceAfterAnswerSelection() {
        guard viewModel.currentStep == displayedStep,
              viewModel.shouldAutoAdvanceAfterAnswerSelection else { return }
        handleContinue()
    }

    /// The outgoing step must adopt the new direction before it is removed,
    /// so the direction is applied one update ahead of the step change.
    private func show(_ step: ProfileCreationStep) {
        guard step != displayedStep else { return }
        direction = step > displayedStep ? .forward : .backward
        isNavigating = true
        navigationToken += 1
        let token = navigationToken

        DispatchQueue.main.async {
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.step, reduceMotion: reduceMotion)) {
                displayedStep = step
            }
        }
        Task {
            try? await Task.sleep(for: OnboardingMotion.stepLock)
            guard token == navigationToken else { return }
            isNavigating = false
            isTitleFocused = true
        }
    }
}

/// Shown over the dimmed onboarding before returning to the locked landing.
struct UnderageNoticeView: View {
    var body: some View {
        Text(L10n("Minors not allowed."))
            .font(.system(.largeTitle, weight: .semibold))
            .tracking(-0.5)
            .foregroundStyle(OnboardingTheme.primaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .shadow(color: OnboardingTheme.blue.opacity(0.6), radius: 24)
            .accessibilityAddTraits(.isHeader)
    }
}

extension AnyTransition {
    static func underageNotice(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: 0.94).combined(with: .opacity).combined(with: .onboardingReveal(reduceMotion: false))
    }
}
