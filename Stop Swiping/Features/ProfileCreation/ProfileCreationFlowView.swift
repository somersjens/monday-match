import SwiftUI

/// The step container: progress, the animated step, and Continue / Back. It
/// is transparent so it can sit directly on the landing page's light.
struct ProfileCreationFlowView: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    @ObservedObject var locationService: LocationService
    /// The first step can return to the landing page when one is behind it.
    let canExitFromFirstStep: Bool
    /// The early-adopter deadline shown beside the progress; nil hides it.
    let countdownDeadline: Date?
    let onExit: () -> Void
    let onUnderage: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedStep: ProfileCreationStep
    @State private var direction: StepDirection = .forward
    @State private var isNavigating = false
    @State private var navigationToken = 0
    @State private var pendingAutoAdvance: Task<Void, Never>?
    @State private var hasEntered = false
    /// Changing one answer of a finished profile shows the step dots; filling
    /// in the questionnaire shows the progress card.
    @State private var isEditingSession: Bool
    /// The last question was answered and the closing moment is playing.
    @State private var finish = FinishPhase.none
    /// Holding Continue on the birthday fills in every question at random.
    @State private var randomFills = 0
    /// Set when the hold fired, so the release that ends it is no Continue.
    @State private var ignoresNextContinue = false
    /// A Continue on the untouched height step brought up the honesty notice.
    @State private var hasRevealedHeightNotice = false
    /// The notice is on screen. It leaves with the height step and rises
    /// again on every return, so it is never just already there.
    @State private var isHeightNoticeShown = false
    /// A minor birthday waiting for the user to confirm it.
    @State private var ageToConfirm: Int?
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(
        viewModel: ProfileCreationViewModel,
        locationService: LocationService,
        canExitFromFirstStep: Bool,
        countdownDeadline: Date? = nil,
        onExit: @escaping () -> Void,
        onUnderage: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.locationService = locationService
        self.canExitFromFirstStep = canExitFromFirstStep
        self.countdownDeadline = countdownDeadline
        self.onExit = onExit
        self.onUnderage = onUnderage
        self.onComplete = onComplete
        _displayedStep = State(initialValue: viewModel.currentStep)
        _isEditingSession = State(initialValue: viewModel.editingStep != nil)
    }

    private enum FinishPhase: Comparable {
        case none
        /// The bar fills to 100% while the question gives way.
        case filled
        /// The card glows and the countdown gives way to a checkmark.
        case sealed
        /// Everything softens away into the finished profile.
        case leaving
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
            progressHeader

            ZStack(alignment: .top) {
                stepPage(displayedStep)
                    .allowsHitTesting(!isNavigating)
                    .id(displayedStep)
                    .transition(.onboardingStep(direction, reduceMotion: reduceMotion))
                    .opacity(finish == .none ? 1 : 0)
                    .blur(radius: finish == .none || reduceMotion ? 0 : 14)
                    .scaleEffect(finish == .none || reduceMotion ? 1 : 0.96, anchor: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered || reduceMotion ? 0 : 28)
            .blur(radius: hasEntered || reduceMotion ? 0 : 10)

            bottomBar
                .opacity(finish == .none ? 1 : 0)
                .blur(radius: finish == .none || reduceMotion ? 0 : 8)
                .allowsHitTesting(finish == .none)
        }
        // The question steps back while the age is being confirmed.
        .blur(radius: ageToConfirm == nil || reduceMotion ? 0 : 12)
        .opacity(ageToConfirm == nil ? 1 : 0.25)
        .allowsHitTesting(ageToConfirm == nil)
        .accessibilityHidden(ageToConfirm != nil)
        .overlay {
            if let age = ageToConfirm {
                AgeConfirmationCard(age: age, onConfirm: confirmUnderage, onCorrect: correctBirthday)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: OnboardingTheme.contentWidth)
                    .transition(.underageNotice(reduceMotion: reduceMotion))
            }
        }
        // On iPad the questionnaire stays one composition, its buttons near
        // the question, at the height the landing controls use.
        .adaptiveStageHeight()
        .opacity(finish == .leaving ? 0 : 1)
        .blur(radius: finish == .leaving && !reduceMotion ? 12 : 0)
        .onAppear {
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion).delay(reduceMotion ? 0 : 0.12)) {
                hasEntered = true
            }
            revealHeightNoticeIfSeen(after: .milliseconds(700))
        }
        .onChange(of: viewModel.state.hasAdjustedHeight) { _, adjusted in
            if adjusted, displayedStep == .height { isHeightNoticeShown = true }
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
        .sensoryFeedback(.warning, trigger: ageToConfirm) { _, age in age != nil }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: displayedStep)
        .sensoryFeedback(.success, trigger: finish) { _, phase in phase == .filled }
        .sensoryFeedback(.success, trigger: randomFills)
        .soundFeedback(.rejection, trigger: viewModel.rejectionCount)
        // Each step a note higher, so the questionnaire climbs like a melody.
        .soundFeedback(trigger: displayedStep) { _, step in .step(step.number) }
        .soundFeedback(.seal, trigger: finish) { _, phase in phase == .sealed }
        .soundFeedback(.success, trigger: randomFills)
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressHeader: some View {
        if isEditingSession {
            OnboardingProgressDots(current: displayedStep.number, total: ProfileCreationStep.allCases.count)
                .padding(.top, 2)
                .opacity(hasEntered ? 1 : 0)
        } else {
            OnboardingProgressCard(progress: finish == .none ? viewModel.state.progress : 1,
                                   deadline: countdownDeadline,
                                   isFinished: finish >= .sealed)
                // Snug under the status bar, close to the question below.
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
                .frame(maxWidth: OnboardingTheme.contentWidth)
                .frame(maxWidth: .infinity)
                .scaleEffect(finish == .leaving && !reduceMotion ? 1.04 : 1)
                .opacity(hasEntered ? 1 : 0)
                .offset(y: hasEntered || reduceMotion ? 0 : -12)
        }
    }

    /// The bar fills, the card seals with a checkmark, and the screen softens
    /// into the finished profile before handing over.
    private func playFinish() {
        let timing: (seal: Double, leave: Double, hand: Double) = reduceMotion
            ? (0.15, 0.8, 0.2) : (0.55, 1.2, 0.35)
        withAnimation(OnboardingMotion.resolved(.spring(duration: 0.6, bounce: 0.1), reduceMotion: reduceMotion)) {
            finish = .filled
        }
        Task {
            try? await Task.sleep(for: .seconds(timing.seal))
            withAnimation(OnboardingMotion.resolved(.spring(duration: 0.55, bounce: 0.2), reduceMotion: reduceMotion)) {
                finish = .sealed
            }
            try? await Task.sleep(for: .seconds(timing.leave))
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45)) {
                finish = .leaving
            }
            try? await Task.sleep(for: .seconds(timing.hand))
            onComplete()
        }
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
                        subtitle: step == .religion ? nil : step.subtitle,
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
        default:
            if let question = step.compatibilityQuestion {
                CompatibilityScaleStep(viewModel: viewModel, question: question, onAnswerSelected: advanceAfterAnswerSelection)
            }
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

            if showsHeightHonestyNotice {
                heightHonestyNotice
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }

            if let text = partnerHeightNoticeText {
                partnerHeightNotice(text)
                    .transition(.onboardingReveal(reduceMotion: reduceMotion))
            }

            Button(action: handleContinue) {
                Text(primaryTitle)
                    .contentTransition(.opacity)
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(!viewModel.canContinue)
            .simultaneousGesture(randomFillHold)

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
        .controlsBottomPadding()
        .opacity(hasEntered ? 1 : 0)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: showsHeightHonestyNotice)
        .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: partnerHeightNoticeText)
    }

    /// Appears once a height has been chosen, or after a first Continue on
    /// the untouched default, so nobody skips past it unseen.
    private var showsHeightHonestyNotice: Bool {
        displayedStep == .height && isHeightNoticeShown
    }

    /// Back on the height step, a notice seen before rises again once the
    /// page has settled.
    private func revealHeightNoticeIfSeen(after delay: Duration) {
        guard displayedStep == .height,
              viewModel.state.hasAdjustedHeight || hasRevealedHeightNotice else { return }
        Task {
            try? await Task.sleep(for: delay)
            guard displayedStep == .height else { return }
            isHeightNoticeShown = true
        }
    }

    /// One centred line in a red frame, so it reads as a warning at a glance.
    private var heightHonestyNotice: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Text(L10n("False information can lead to account termination."))
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(OnboardingTheme.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                shape
                    .fill(OnboardingTheme.destructive.opacity(0.12))
                    .overlay {
                        shape.strokeBorder(DestructiveGlowButtonStyle.gradient, lineWidth: 1.5)
                    }
                    .shadow(color: OnboardingTheme.destructive.opacity(0.35), radius: 14, y: 4)
            }
    }

    /// On the partner-height step, when the chosen range leaves out the
    /// user's own height: allowed, just worth knowing.
    private var partnerHeightNoticeText: String? {
        guard displayedStep == .partnerHeightRange else { return nil }
        let own = viewModel.state.heightCentimeters
        let range = viewModel.state.partnerHeightRange
        if range.minimum > own {
            return L10n("That’s fine. Just know that everyone in this range is taller than you.")
        }
        if range.maximum < own {
            return L10n("That’s fine. Just know that everyone in this range is shorter than you.")
        }
        return nil
    }

    private func partnerHeightNotice(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(OnboardingTheme.secondaryText)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
            .contentTransition(.opacity)
    }

    // MARK: - Testing shortcut

    /// Three seconds on Continue at the birthday answers every question at
    /// random and opens the last one. Deliberately in every build, for testing.
    private var randomFillHold: some Gesture {
        LongPressGesture(minimumDuration: 3)
            .onEnded { _ in fillRandomly() }
            .simultaneously(with: DragGesture(minimumDistance: 0).onEnded { _ in
                // The button's own action runs on this same release first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ignoresNextContinue = false }
            })
    }

    private func fillRandomly() {
        guard displayedStep == .dateOfBirth, !isEditingSession, !isNavigating, finish == .none else { return }
        ignoresNextContinue = true
        randomFills += 1
        viewModel.fillRandomAnswersForTesting()
    }

    // MARK: - Navigation

    private func handleContinue() {
        if ignoresNextContinue {
            ignoresNextContinue = false
            return
        }
        guard !isNavigating, ageToConfirm == nil else { return }
        // The first Continue on an untouched height only reveals the notice;
        // the next one moves on.
        if displayedStep == .height, !showsHeightHonestyNotice {
            hasRevealedHeightNotice = true
            isHeightNoticeShown = true
            AccessibilityNotification.Announcement(L10n("False information can lead to account termination.")).post()
            return
        }
        handleSubmission(viewModel.submitCurrentStep())
    }

    private func handleSubmission(_ submission: ProfileCreationSubmission) {
        switch submission {
        case .advanced:
            isNavigating = viewModel.currentStep != displayedStep
        case .rejected:
            break
        case .confirmAge(let age):
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
                ageToConfirm = age
            }
        case .underage:
            isNavigating = true
            onUnderage()
        case .completed:
            isNavigating = true
            if isEditingSession { onComplete() } else { playFinish() }
        }
    }

    /// The user stands by the minor birthday: the lock follows.
    private func confirmUnderage() {
        // The card gives way to the landing's own Minors notice.
        withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
            ageToConfirm = nil
        }
        handleSubmission(viewModel.confirmUnderage())
    }

    /// Back to the wheels, with the entered date still set.
    private func correctBirthday() {
        withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
            ageToConfirm = nil
        }
        isTitleFocused = true
    }

    private func handleBack() {
        guard !isNavigating, ageToConfirm == nil else { return }
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

    /// Lets the tapped answer visibly settle before the page moves on, and
    /// restarts on every new tap so changing your mind never skips ahead.
    private func advanceAfterAnswerSelection() {
        pendingAutoAdvance?.cancel()
        let step = viewModel.currentStep
        guard step == displayedStep,
              viewModel.shouldAutoAdvanceAfterAnswerSelection else { return }
        pendingAutoAdvance = Task {
            try? await Task.sleep(for: OnboardingMotion.answerSettle)
            guard !Task.isCancelled,
                  viewModel.currentStep == step, displayedStep == step,
                  viewModel.shouldAutoAdvanceAfterAnswerSelection else { return }
            handleContinue()
        }
    }

    /// The outgoing step must adopt the new direction before it is removed,
    /// so the direction is applied one update ahead of the step change.
    private func show(_ step: ProfileCreationStep) {
        guard step != displayedStep else { return }
        pendingAutoAdvance?.cancel()
        isHeightNoticeShown = false
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
            revealHeightNoticeIfSeen(after: .milliseconds(120))
        }
    }
}

/// Asks a user whose birthday makes them a minor whether that is right,
/// before anything is locked or discarded.
private struct AgeConfirmationCard: View {
    let age: Int
    let onConfirm: () -> Void
    let onCorrect: () -> Void

    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("\(age)")
                    .font(.system(size: 64, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .shadow(color: OnboardingTheme.blue.opacity(0.5), radius: 18)
                    .accessibilityHidden(true)
                Text(L10n("Are you really \(age)?"))
                    .font(.system(.title2, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                Button(L10n("Yes, I am \(age)"), action: onConfirm)
                    .buttonStyle(GlowButtonStyle())
                Button(L10n("No, change my birthday"), action: onCorrect)
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxWidth: OnboardingTheme.controlWidth)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(OnboardingTheme.background.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LinearGradient(
                            colors: [OnboardingTheme.blue.opacity(0.14), OnboardingTheme.violet.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(OnboardingTheme.accentGradient.opacity(0.5), lineWidth: 1)
                }
                .shadow(color: OnboardingTheme.blue.opacity(0.3), radius: 30, y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { isTitleFocused = true }
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
