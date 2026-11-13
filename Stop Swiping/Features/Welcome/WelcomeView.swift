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
    @State private var showsAutoMatching = false
    /// Where the light is drawn. It trails `stage` while the helix replaces
    /// the heart out of view.
    @State private var lightStage: Stage
    @State private var isLightHidden = false
    @State private var showsCode = false

    @StateObject private var savedMatches = SavedMatchStore()
    /// The match shown in place of the home controls.
    @State private var activeMatch: ActiveMatch?
    /// What the light draws. It trails `activeMatch` while the heart fades out.
    @State private var lightMatch: WelcomeLightMatch.Request?
    @State private var matchReveal = MatchReveal.hidden
    @State private var matchTask: Task<Void, Never>?
    @State private var scoreDetail: MatchReport.Perspective?
    @State private var showsSavedMatches = false
    @State private var demoStarts = 0
    @State private var nameNudges = 0
    @FocusState private var isNameFocused: Bool
    /// The tallest layout seen at this width. The keyboard shrinks the
    /// layout, but the light stays where it is.
    @State private var lightLayoutSize = CGSize.zero

    private struct ActiveMatch: Equatable {
        let snapshot: MatchSnapshot
        let report: MatchReport
    }

    /// Holding Share profile this long starts a demo match.
    private static let demoHoldDuration = 3.0

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
            let layoutHeight = lightLayoutSize.width == proxy.size.width
                ? max(lightLayoutSize.height, proxy.size.height) : proxy.size.height
            let animationHeight = max(0, layoutHeight - 160)
            let animationWidth = min(proxy.size.width, 620)
            let lightHeight = min(proxy.size.width * 1.12, animationHeight * 0.94)
            // Extend the drawable past the incoming tail while keeping the
            // light's scale, centre and stage transitions in the same place.
            let drawingHeight = max(animationWidth * 2.1, lightHeight)
            // Far enough that each waiting backbone starts just past its side
            // of the light's frame.
            let sideEntry = animationWidth / 2 + 24

            ZStack {
                Color("WelcomeBackground")
                    .ignoresSafeArea()

                // The same light continues into onboarding. Only its transform
                // and opacity change, so the Metal surface is never resized.
                WelcomeLightAnimation(form: lightForm, lockPulse: lockPulse,
                                      showsCode: showsCode, skipsEntrance: skipsEntrance,
                                      isPaused: showsOverview || showsAutoMatching || showsSavedMatches,
                                      framesPerSecond: isOnboarding ? 30 : 60,
                                      helixEntryDistance: sideEntry / max(animationWidth * 0.42, 1)
                                        + WelcomeLightHelix.radius + 0.12,
                                      match: lightMatch)
                    .frame(width: animationWidth, height: drawingHeight)
                    .scaleEffect(isOnboarding ? 0.62 : 1)
                    .opacity(isLightHidden ? 0 : (isOnboarding ? (showsUnderageNotice ? 0.55 : 0.3) : 1))
                    .position(
                        x: proxy.size.width / 2,
                        y: isOnboarding ? min(36, animationHeight / 2) : animationHeight / 2
                    )

                if stage == .complete && lightStage == .complete && canShowCode && activeMatch == nil {
                    Button(action: toggleCode) {
                        Color.clear
                            .frame(width: min(proxy.size.width, 620) * 0.6, height: lightHeight * 0.85)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: proxy.size.width / 2, y: animationHeight / 2)
                    .disabled(isTransitioning)
                    .accessibilityLabel(showsCode ? L10n("QR code") : L10n("Your profile DNA"))
                    .accessibilityHint(showsCode ? L10n("Turns back into your DNA.") : L10n("Turns into a QR code."))
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
                } else if stage == .complete, let activeMatch {
                    MatchResultOverlay(
                        match: activeMatch.snapshot,
                        report: activeMatch.report,
                        frame: MatchStageFrame(
                            center: CGPoint(x: proxy.size.width / 2, y: animationHeight / 2),
                            unit: animationWidth * 0.42
                        ),
                        reveal: matchReveal,
                        isSaved: savedMatches.contains(activeMatch.snapshot.id),
                        onShowScores: { scoreDetail = $0 },
                        onSave: { saveMatch(activeMatch.snapshot) },
                        onClose: closeMatch,
                        onDelete: { deleteMatch(activeMatch.snapshot) }
                    )
                    .transition(.opacity)
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Growing never comes from the keyboard; shrinking only does while typing.
            if size.width != lightLayoutSize.width || size.height > lightLayoutSize.height || !isNameFocused {
                lightLayoutSize = size
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: lockPulse)
        .sensoryFeedback(.error, trigger: showsUnderageNotice) { _, shown in shown }
        .sensoryFeedback(.success, trigger: demoStarts)
        .sensoryFeedback(.warning, trigger: nameNudges)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { profileCreation.persist() }
        }
        .fullScreenCover(isPresented: $showsOverview) {
            ProfileOverviewView(viewModel: profileCreation, locationService: locationService,
                                onUnderage: showUnderageNotice)
        }
        .fullScreenCover(isPresented: $showsAutoMatching) {
            AutoMatchingSetupView(viewModel: profileCreation, locationService: locationService) {
                showsAutoMatching = false
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showsSavedMatches) {
            SavedMatchesView(store: savedMatches, onOpen: openSavedMatch)
        }
        .sheet(item: $scoreDetail) { perspective in
            if let activeMatch {
                MatchScoreDetailView(report: activeMatch.report, perspective: perspective,
                                     name: activeMatch.snapshot.name)
            }
        }
        .onAppear {
            if lightStage == .complete { waitForHelixEntrance() }
        }
    }

    private var landingControls: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if profileCreation.isUnderageLocked {
                    Label(L10n("Minors not allowed."), systemImage: "lock.fill")
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .padding(.bottom, 4)
                        .transition(.onboardingReveal(reduceMotion: reduceMotion))
                }

                Button(L10n("Get started"), action: handleGetStarted)
                    .buttonStyle(GlowButtonStyle())

                Button(L10n("I already have an account"), action: onSignIn)
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
                // A name comes first; auto matching appears once it is saved.
                Group {
                    if profileCreation.hasDisplayName {
                        AutoMatchingCard(viewModel: profileCreation) {
                            guard !isTransitioning else { return }
                            showsAutoMatching = true
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        ProfileNameCard(viewModel: profileCreation, isFocused: $isNameFocused)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
                .padding(.bottom, 4)

                Button(showsCode ? L10n("Show your helix") : L10n("Share profile"), action: toggleCode)
                    .buttonStyle(GlowButtonStyle())
                    .disabled(isTransitioning || !canShowCode)
                    // Before launch there is nobody to match with: holding
                    // the button plays a demo match instead.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: Self.demoHoldDuration)
                            .onEnded { _ in startDemoMatch() }
                    )
                    .accessibilityHint(showsCode ? L10n("Shows your profile DNA.") : L10n("Shows your QR code."))
                    .accessibilityAction(named: L10n("Start a demo match"), startDemoMatch)

                HStack(spacing: 8) {
                    Button(L10n("Adjust profile"), action: adjustProfile)
                        .buttonStyle(QuietButtonStyle())
                    if !savedMatches.matches.isEmpty {
                        Button(L10n("Saved matches"), action: openSavedMatches)
                            .buttonStyle(QuietButtonStyle())
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                       value: profileCreation.hasDisplayName)
            .animation(.easeInOut(duration: 0.25), value: savedMatches.matches.isEmpty)
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
        guard !isTransitioning, activeMatch == nil else { return }
        showsCode.toggle()
    }

    // MARK: - Matches

    private func startDemoMatch() {
        guard stage == .complete, lightStage == .complete, activeMatch == nil, !isTransitioning else { return }
        guard profileCreation.hasDisplayName else {
            nameNudges += 1
            isNameFocused = true
            return
        }
        var generator = SystemRandomNumberGenerator()
        let snapshot = DemoMatchGenerator.makeMatch(for: profileCreation.state,
                                                    shouldMatch: DemoMatchSchedule.next(),
                                                    using: &generator)
        demoStarts += 1
        present(snapshot)
    }

    /// The helix streams up and returns as the match heart; the labels
    /// follow the light's own timeline.
    private func present(_ snapshot: MatchSnapshot) {
        let report = snapshot.report
        isTransitioning = true
        isNameFocused = false
        showsCode = false
        matchReveal = .hidden
        withAnimation(.easeOut(duration: 0.35)) {
            activeMatch = ActiveMatch(snapshot: snapshot, report: report)
        }
        lightMatch = WelcomeLightMatch.Request(id: snapshot.id, isMatch: report.isMatch)
        AccessibilityNotification.Announcement(report.isMatch
            ? L10n("\(report.average) percent, a match with \(snapshot.name).")
            : L10n("\(report.average) percent, no match with \(snapshot.name).")).post()
        matchTask?.cancel()
        matchTask = Task {
            var beats: [(Double, MatchReveal)] = [
                (WelcomeLightMatch.averageRevealTime, .average),
                (WelcomeLightMatch.scoresRevealTime, .scores)
            ]
            if !report.isMatch { beats.append((WelcomeLightMatch.issuesRevealTime, .issues)) }
            beats.append((WelcomeLightMatch.controlsRevealTime(isMatch: report.isMatch), .controls))
            var elapsed = 0.0
            for (time, step) in beats {
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(max(0, time - elapsed)))
                    elapsed = time
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.6)) { matchReveal = step }
            }
            isTransitioning = false
        }
    }

    private func saveMatch(_ snapshot: MatchSnapshot) {
        savedMatches.save(snapshot)
        AccessibilityNotification.Announcement(L10n("Match saved.")).post()
    }

    private func deleteMatch(_ snapshot: MatchSnapshot) {
        savedMatches.delete(snapshot.id)
        closeMatch()
    }

    /// The heart fades where it is, and the helix ropes back in from the sides.
    private func closeMatch() {
        guard activeMatch != nil else { return }
        matchTask?.cancel()
        isTransitioning = true
        scoreDetail = nil
        Task {
            withAnimation(.easeOut(duration: 0.3)) {
                activeMatch = nil
                matchReveal = .hidden
                if !reduceMotion { isLightHidden = true }
            }
            if !reduceMotion { try? await Task.sleep(for: .seconds(0.3)) }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                lightMatch = nil
                isLightHidden = false
            }
            waitForHelixEntrance()
        }
    }

    private func openSavedMatches() {
        guard !isTransitioning, activeMatch == nil else { return }
        showsCode = false
        showsSavedMatches = true
    }

    private func openSavedMatch(_ snapshot: MatchSnapshot) {
        showsSavedMatches = false
        Task {
            // Let the cover finish closing before the helix starts to leave.
            try? await Task.sleep(for: .seconds(0.45))
            present(snapshot)
        }
    }

    /// The heart fades where it is; the helix turns in from below the screen
    /// on its renderer's clock, passing behind the controls.
    private func showCompletion() {
        isTransitioning = true
        AccessibilityNotification.Announcement(L10n("Your profile is complete.")).post()
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
                lightStage = .complete
                isLightHidden = false
            }
            waitForHelixEntrance()
        }
    }

    private func waitForHelixEntrance() {
        isTransitioning = true
        Task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(WelcomeLightHelix.Arrival.delay + WelcomeLightHelix.Arrival.duration))
            }
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
        AccessibilityNotification.Announcement(L10n("Minors not allowed.")).post()
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
        AccessibilityNotification.Announcement(L10n("Minors not allowed.")).post()
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
