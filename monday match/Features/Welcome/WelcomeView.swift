import SwiftUI

struct WelcomeView: View {
    let onSignIn: () -> Void

    @StateObject private var profileCreation: ProfileCreationViewModel
    @StateObject private var locationService = LocationService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    @State private var showsUnderageNotice = false
    @State private var isTransitioning = false
    @State private var lockPulse = 0
    @State private var resetTapCount = 0
    @State private var lastResetTap: Date?
    @State private var showsOverview = false
    /// Where the light is drawn. It trails `stage` while the helix replaces
    /// the heart out of view.
    @State private var lightStage: Stage
    /// The helix waits below the screen, as a fraction of its height, and
    /// rises into place behind the controls.
    @State private var helixDrop: CGFloat
    @State private var isLightHidden = false
    @State private var showsCode = false

    private enum Stage {
        case landing
        case onboarding
        /// The finished profile, shown as the light's double helix.
        case complete
    }

    /// Taps on Get started while locked that restart the birthday step.
    private static let resetTapThreshold = 10
    private static let resetTapWindow: TimeInterval = 3

    init(
        profileCreationStore: ProfileCreationStateStoring,
        repository: ProfileRepository?,
        onSignIn: @escaping () -> Void
    ) {
        self.onSignIn = onSignIn
        let model = ProfileCreationViewModel(store: profileCreationStore, repository: repository)
        _profileCreation = StateObject(wrappedValue: model)
        let stage: Stage = model.isCompleted ? .complete : .landing
        _stage = State(initialValue: stage)
        _lightStage = State(initialValue: stage)
        _helixDrop = State(initialValue: stage == .complete ? 1 : 0)
        skipsEntrance = stage == .complete
    }

    private let skipsEntrance: Bool
    private var isOnboarding: Bool { lightStage == .onboarding }
    private var canShowCode: Bool { WelcomeLightMetalView.isAvailable && WelcomeLightCode.isAvailable }

    private var lightForm: WelcomeLightForm {
        switch lightStage {
        case .landing: profileCreation.isUnderageLocked ? .lock : .heart
        case .onboarding: .heart
        case .complete: .helix
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let animationHeight = max(0, proxy.size.height - 160)
            let animationWidth = min(proxy.size.width, 620)
            let lightHeight = min(proxy.size.width * 1.12, animationHeight * 0.94)
            // Extend the drawable past the incoming tail while keeping the
            // light's scale, centre and stage transitions in the same place.
            let drawingHeight = max(animationWidth * 2.1, lightHeight)
            // Far enough that the waiting helix sits wholly below the screen.
            let hiddenDrop = proxy.size.height - (animationHeight - lightHeight) / 2 + 60

            ZStack {
                Color("WelcomeBackground")
                    .ignoresSafeArea()

                // The same light continues into onboarding. Only its transform
                // and opacity change, so the Metal surface is never resized.
                WelcomeLightAnimation(form: lightForm, lockPulse: lockPulse,
                                      showsCode: showsCode, skipsEntrance: skipsEntrance,
                                      isPaused: showsOverview)
                    .frame(width: animationWidth, height: drawingHeight)
                    .scaleEffect(isOnboarding ? 0.62 : 1)
                    .opacity(isLightHidden ? 0 : (isOnboarding ? (showsUnderageNotice ? 0.55 : 0.3) : 1))
                    .position(
                        x: proxy.size.width / 2,
                        y: isOnboarding ? min(36, animationHeight / 2) : animationHeight / 2
                    )
                    .offset(y: helixDrop * hiddenDrop)

                if stage == .complete && lightStage == .complete && canShowCode {
                    Button(action: toggleCode) {
                        Color.clear
                            .frame(width: min(proxy.size.width, 620) * 0.6, height: lightHeight * 0.85)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: proxy.size.width / 2, y: animationHeight / 2)
                    .disabled(isTransitioning)
                    .accessibilityLabel(showsCode ? "QR code" : "Your profile DNA")
                    .accessibilityHint(showsCode ? "Turns back into your DNA." : "Turns into a QR code.")
                }

                if isOnboarding {
                    ProfileCreationFlowView(
                        viewModel: profileCreation,
                        locationService: locationService,
                        canExitFromFirstStep: true,
                        onExit: returnToLanding,
                        onUnderage: showUnderageNotice,
                        onComplete: showCompletion
                    )
                    .blur(radius: showsUnderageNotice && !reduceMotion ? 18 : 0)
                    .opacity(showsUnderageNotice ? 0.15 : 1)
                    .allowsHitTesting(!showsUnderageNotice)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                } else if stage == .complete {
                    completionControls
                        .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                } else {
                    landingControls
                        .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                }

                if showsUnderageNotice {
                    UnderageNoticeView()
                        .transition(.underageNotice(reduceMotion: reduceMotion))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: lockPulse)
        .sensoryFeedback(.error, trigger: showsUnderageNotice) { _, shown in shown }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { profileCreation.persist() }
        }
        .fullScreenCover(isPresented: $showsOverview) {
            ProfileOverviewView(viewModel: profileCreation, locationService: locationService,
                                onUnderage: showUnderageNotice)
        }
        .onAppear {
            if lightStage == .complete && helixDrop > 0 { riseHelix(delay: 0.35) }
        }
    }

    private var landingControls: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if profileCreation.isUnderageLocked {
                    Label("Minors not allowed.", systemImage: "lock.fill")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .padding(.bottom, 4)
                        .transition(.onboardingReveal(reduceMotion: reduceMotion))
                }

                Button("Get started", action: handleGetStarted)
                    .buttonStyle(GlowButtonStyle())

                Button("I already have an account", action: onSignIn)
                    .buttonStyle(QuietButtonStyle())
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                       value: profileCreation.isUnderageLocked)
        }
    }

    private var completionControls: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Label("Your profile is complete.", systemImage: "checkmark.seal.fill")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .padding(.bottom, 4)

                Button("Adjust profile", action: adjustProfile)
                    .buttonStyle(GlowButtonStyle())
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            // Keeps the button where Get started sits, above the account link.
            .padding(.bottom, 18 + 12 + 48)
        }
    }

    // MARK: - Stage changes

    private func handleGetStarted() {
        guard !isTransitioning else { return }
        guard profileCreation.isUnderageLocked else {
            openOnboarding()
            return
        }
        registerResetTap()
    }

    /// Restarting only reopens the empty birthday step; the age is validated
    /// again from scratch, and the lock carries no access decision itself.
    private func registerResetTap() {
        let now = Date()
        if let lastResetTap, now.timeIntervalSince(lastResetTap) > Self.resetTapWindow {
            resetTapCount = 0
        }
        lastResetTap = now
        resetTapCount += 1
        lockPulse += 1

        guard resetTapCount >= Self.resetTapThreshold else { return }
        resetTapCount = 0
        self.lastResetTap = nil
        profileCreation.restartAfterUnderageLock()
        openOnboarding(delay: reduceMotion ? 0 : 0.9)
    }

    private func openOnboarding(delay: Double = 0) {
        isTransitioning = true
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion)) {
                stage = .onboarding
                lightStage = .onboarding
            }
            try? await Task.sleep(for: OnboardingMotion.stepLock)
            isTransitioning = false
        }
    }

    private func adjustProfile() {
        guard !isTransitioning else { return }
        showsOverview = true
    }

    private func toggleCode() {
        guard !isTransitioning else { return }
        showsCode.toggle()
    }

    /// The heart fades where it is; the helix then rises from below the
    /// screen, passing behind the button, instead of growing out of it.
    private func showCompletion() {
        isTransitioning = true
        AccessibilityNotification.Announcement("Your profile is complete.").post()
        Task {
            guard !reduceMotion else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    stage = .complete
                    lightStage = .complete
                }
                isTransitioning = false
                return
            }
            withAnimation(.easeOut(duration: 0.3)) { isLightHidden = true }
            withAnimation(OnboardingMotion.stage) { stage = .complete }
            try? await Task.sleep(for: .seconds(0.3))
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                helixDrop = 1
                lightStage = .complete
                isLightHidden = false
            }
            riseHelix(delay: 0.05)
        }
    }

    private func riseHelix(delay: Double) {
        isTransitioning = true
        Task {
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.spring(duration: 1.9, bounce: 0.08)) { helixDrop = 0 }
            try? await Task.sleep(for: .seconds(1.4))
            isTransitioning = false
        }
    }

    /// Leaving the first question returns to wherever the user came from.
    private func returnToLanding() {
        isTransitioning = true
        profileCreation.persist()
        Task {
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion)) {
                stage = .landing
                lightStage = .landing
            }
            try? await Task.sleep(for: OnboardingMotion.stepLock)
            isTransitioning = false
        }
    }

    private func showUnderageNotice() {
        isTransitioning = true
        showsCode = false
        withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
            showsUnderageNotice = true
        }
        AccessibilityNotification.Announcement("Minors not allowed.").post()
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 2.4 : 1.8))
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion)) {
                showsUnderageNotice = false
                stage = .landing
                lightStage = .landing
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : WelcomeLightLock.morphDuration))
            isTransitioning = false
        }
    }
}

/// Profile creation for accounts that reach onboarding without it, shown on
/// the same ambient light as the landing page.
struct ProfileCreationGateView: View {
    let onComplete: () -> Void
    let onUnderage: () -> Void

    @StateObject private var viewModel: ProfileCreationViewModel
    @StateObject private var locationService = LocationService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsUnderageNotice = false

    init(
        store: ProfileCreationStateStoring,
        repository: ProfileRepository?,
        onComplete: @escaping () -> Void,
        onUnderage: @escaping () -> Void
    ) {
        self.onComplete = onComplete
        self.onUnderage = onUnderage
        _viewModel = StateObject(wrappedValue: ProfileCreationViewModel(store: store, repository: repository))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingTheme.background
                    .ignoresSafeArea()

                WelcomeLightAnimation()
                    .frame(width: min(proxy.size.width, 620), height: min(proxy.size.width * 1.12, max(0, proxy.size.height - 160) * 0.94))
                    .scaleEffect(0.62)
                    .opacity(0.3)
                    .position(x: proxy.size.width / 2, y: 36)

                ProfileCreationFlowView(
                    viewModel: viewModel,
                    locationService: locationService,
                    canExitFromFirstStep: false,
                    onExit: {},
                    onUnderage: handleUnderage,
                    onComplete: onComplete
                )
                .blur(radius: showsUnderageNotice && !reduceMotion ? 18 : 0)
                .opacity(showsUnderageNotice ? 0.15 : 1)
                .allowsHitTesting(!showsUnderageNotice)

                if showsUnderageNotice {
                    UnderageNoticeView()
                        .transition(.underageNotice(reduceMotion: reduceMotion))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // A device that is already locked goes straight to the locked landing.
            if viewModel.isUnderageLocked { onUnderage() }
        }
    }

    private func handleUnderage() {
        withAnimation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion)) {
            showsUnderageNotice = true
        }
        AccessibilityNotification.Announcement("Minors not allowed.").post()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            onUnderage()
        }
    }
}

#Preview {
    NavigationStack {
        WelcomeView(
            profileCreationStore: InMemoryProfileCreationStore(),
            repository: InMemoryProfileRepository(),
            onSignIn: {}
        )
    }
}
