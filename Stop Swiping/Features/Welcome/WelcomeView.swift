import SwiftUI

struct WelcomeView: View {
    let onSignIn: () -> Void
    private let onAccountCreated: () -> Void
    private let authService: AuthServicing
    private let profileSync: ProfileCloudSyncing?
    private let chatRepository: SecureChatRepository?
    private let photoVerification: AWSPhotoVerificationService?
    private let automaticallyShowsAccessOnAppear: Bool
    @ObservedObject var access: LifetimeAccessStore
    /// Codes scanned outside the app, with the iPhone's own camera.
    @ObservedObject private var codeInbox: ProfileCodeInbox
    @State private var showsAccess = false

    @StateObject private var profileCreation: ProfileCreationViewModel
    @StateObject private var locationService = LocationService()
    @StateObject private var notifications = NotificationPermissionService()
    @State private var hasAccount: Bool
    @State private var showsCreateAccount = false
    @State private var hasLoadedNotifications = false
    @State private var profileSyncFailed = false
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
    /// The profile as a code. It stays while the code turns back into the helix.
    @State private var shareCode: WelcomeLightCode.Matrix?
    @State private var showsScanner = false
    /// A profile read by the in-app scanner, waiting for its match to be shown.
    @State private var scannedProfile: ProfileCreationState?

    @StateObject private var savedMatches = SavedMatchStore()
    /// Looks for other phones while the profile is being shared.
    @StateObject private var exchange = ProfileExchangeSession()
    @State private var exchanges = 0
    @State private var showsMatchProfile = false
    /// The match shown in place of the home controls.
    @State private var activeMatch: ActiveMatch?
    /// What the light draws. It trails `activeMatch` while the heart fades out.
    @State private var lightMatch: WelcomeLightMatch.Request?
    @State private var matchReveal = MatchReveal.hidden
    @State private var matchStartedAt = Date()
    @State private var matchTask: Task<Void, Never>?
    @State private var scoreDetail: MatchReport.Perspective?
    @State private var showsSavedMatches = false
    @State private var demoStarts = 0
    @State private var showsProfilePrivacy = false
    @State private var isDemoPlaying = false
    /// The two phones that explain an exchange; nil while this screen is
    /// simply the screen.
    @State private var demoPhase: ExchangeDemo.Phase?
    @State private var demoTask: Task<Void, Never>?
    /// The tallest layout seen at this width. The keyboard shrinks the
    /// layout, but the light stays where it is.
    @State private var lightLayoutSize = CGSize.zero

    private struct ActiveMatch: Equatable {
        let snapshot: MatchSnapshot
        let report: MatchReport
    }

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
        access: LifetimeAccessStore,
        automaticallyShowsAccessOnAppear: Bool = true,
        authService: AuthServicing = MockAuthService(),
        hasAccount: Bool = false,
        profileSync: ProfileCloudSyncing? = nil,
        chatRepository: SecureChatRepository? = nil,
        photoVerification: AWSPhotoVerificationService? = nil,
        codeInbox: ProfileCodeInbox? = nil,
        onAccountCreated: @escaping () -> Void = {},
        onSignIn: @escaping () -> Void
    ) {
        self.codeInbox = codeInbox ?? ProfileCodeInbox()
        self.onSignIn = onSignIn
        self.onAccountCreated = onAccountCreated
        self.authService = authService
        self.profileSync = profileSync
        self.chatRepository = chatRepository
        self.photoVerification = photoVerification
        _hasAccount = State(initialValue: hasAccount)
        self.access = access
        self.automaticallyShowsAccessOnAppear = automaticallyShowsAccessOnAppear
        let model = ProfileCreationViewModel(store: profileCreationStore, repository: repository)
        _profileCreation = StateObject(wrappedValue: model)
        // Closing a required access picker returns to the landing controls,
        // even if an old completed profile is still saved on this device.
        let stage: Stage = model.isCompleted && (automaticallyShowsAccessOnAppear || access.hasAccess)
            ? .complete : .landing
        _stage = State(initialValue: stage)
        _lightStage = State(initialValue: stage)
        skipsEntrance = stage == .complete
    }

    private let skipsEntrance: Bool
    private var isOnboarding: Bool { lightStage == .onboarding }
    private var canShowCode: Bool { WelcomeLightMetalView.isAvailable }

    /// Profiles are only offered while the code is on screen and nothing
    /// else is: the profile can't change underneath an exchange.
    private var isSharing: Bool {
        showsCode && stage == .complete && lightStage == .complete && activeMatch == nil
            && scenePhase == .active && profileCreation.state.canShareProfile
            && !showsOverview && !showsAutoMatching && !showsSavedMatches && !showsAccess && !showsProfilePrivacy && !showsCreateAccount
            && !showsScanner
    }

    /// A scanned profile is matched as soon as the home screen is at rest
    /// with a profile of its own to match against.
    private var canShowScannedMatch: Bool {
        stage == .complete && lightStage == .complete && activeMatch == nil && demoPhase == nil && !isTransitioning
            && scenePhase == .active && profileCreation.state.canShareProfile
            && !showsOverview && !showsAutoMatching && !showsSavedMatches && !showsAccess && !showsProfilePrivacy && !showsCreateAccount
            && !showsScanner
    }

    private var lightForm: WelcomeLightForm {
        switch lightStage {
        case .landing: profileCreation.isUnderageLocked ? .lock : .heart
        case .onboarding: .heart
        case .complete: .helix
        }
    }

    private var restartDemoAction: (() -> Void)? { isDemoPlaying ? { startDemoMatch() } : nil }

    /// This screen as a phone in the explanation.
    private var demoPose: ExchangeDemoPose {
        switch demoPhase {
        case nil, .takeover: .screen
        case .apart: .apart
        case .together, .exchange: .together
        }
    }

    /// The other phone leaves as this one becomes the screen again.
    private var demoPeerPose: ExchangeDemoPose {
        switch demoPhase {
        case nil, .takeover: .gone
        case .apart: .apart
        case .together, .exchange: .together
        }
    }
    private var understandDemoAction: (() -> Void)? { isDemoPlaying ? { understandDemo() } : nil }

    private var sceneContent: some View {
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
            let insets = proxy.safeAreaInsets
            let demoStage = ExchangeDemoStage(size: proxy.size, insets: insets,
                                              helixCenter: animationHeight / 2, helixUnit: animationWidth * 0.42)

            ZStack {
                Color("WelcomeBackground")
                    .ignoresSafeArea()

                // Everything on this phone's screen. The explanation shrinks
                // it into a phone and lets it grow back, light and all.
                ZStack {
                    // The same light continues into onboarding. Only its transform
                    // and opacity change, so the Metal surface is never resized.
                    WelcomeLightAnimation(form: lightForm, lockPulse: lockPulse,
                                          showsCode: showsCode, code: shareCode, skipsEntrance: skipsEntrance,
                                          isPaused: showsOverview || showsAutoMatching || showsSavedMatches || showsProfilePrivacy || showsCreateAccount || showsScanner,
                                          framesPerSecond: isOnboarding ? 30 : 60,
                                          helixEntryDistance: sideEntry / max(animationWidth * 0.42, 1)
                                            + WelcomeLightHelix.radius + 0.12,
                                          match: lightMatch)
                        .frame(width: animationWidth, height: drawingHeight)
                        .scaleEffect(showsAccess ? AccessScreenMotion.lightScale(for: animationWidth) : (isOnboarding ? 0.62 : 1))
                        .opacity(showsAccess ? 1 : (isLightHidden ? 0 : (isOnboarding ? (showsUnderageNotice ? 0.55 : 0.3) : 1)))
                        .position(
                            x: proxy.size.width / 2,
                            y: showsAccess ? AccessScreenMotion.lightCenterY
                                : (isOnboarding ? min(36, animationHeight / 2) : animationHeight / 2)
                        )

                    if !showsAccess && stage == .complete && lightStage == .complete && canShowCode && activeMatch == nil {
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

                        // Fixed to the screen's safe top-right corner.
                        HelixCodeButton(showsCode: showsCode, action: toggleCode)
                            .position(x: proxy.size.width - 16 - HelixCodeButton.size / 2,
                                      y: 8 + HelixCodeButton.size / 2)
                            .disabled(isTransitioning)
                            .opacity(demoPhase == nil ? 1 : 0)
                            .transition(.opacity)

                        // Next to the close button while the code is shown.
                        if showsCode {
                            CodeScanButton(action: openScanner)
                                .position(x: proxy.size.width - 16 - HelixCodeButton.size * 1.5 - 10,
                                          y: 8 + HelixCodeButton.size / 2)
                                .disabled(isTransitioning)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
                        }
                    }

                    if showsAccess {
                        EarlyAccessView(access: access, onContinue: continueFromAccess,
                                        onBack: closeAccess, usesSharedLight: true)
                            .transition(.asymmetric(insertion: .identity,
                                                    removal: .opacity.animation(.easeOut(duration: 0.2))))
                            .zIndex(2)
                    } else if isOnboarding {
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
                            lightTransition: lightMatch?.transition ?? .newMatch,
                            lightStartedAt: matchStartedAt,
                            onShowScores: { scoreDetail = $0 },
                            onShowProfile: { showsMatchProfile = true },
                            onRename: renameMatch,
                            onSave: { saveMatch(activeMatch.snapshot) },
                            onClose: closeMatch,
                            onDelete: { deleteMatch(activeMatch.snapshot) },
                            onRestartDemo: restartDemoAction,
                            onUnderstandDemo: understandDemoAction
                        )
                        .transition(.opacity)
                    } else if stage == .complete, demoPhase != nil {
                        // The explanation's phones show only their light.
                        Color.clear
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
                .modifier(ExchangeDemoPhone(pose: demoPose, side: -1, stage: demoStage, insets: insets,
                                            hidesOverflow: demoPhase != nil))
                .allowsHitTesting(demoPhase == nil)

                if let demoPhase {
                    // Drawn over this phone, so each helix disappears under
                    // the other phone's top edge as it crosses.
                    ExchangeDemoPeerPhone(
                        stage: demoStage,
                        lightSize: CGSize(width: animationWidth, height: drawingHeight),
                        lightCenter: CGPoint(x: insets.leading + proxy.size.width / 2,
                                             y: insets.top + animationHeight / 2),
                        match: demoPhase >= .exchange ? lightMatch : nil,
                        pose: demoPeerPose
                    )
                    .position(x: demoStage.screen.width / 2 - insets.leading,
                              y: demoStage.screen.height / 2 - insets.top)
                    .transition(.asymmetric(insertion: .offset(x: demoStage.screen.width * 0.9), removal: .identity))

                    ExchangeDemoSeam(phase: demoPhase, height: demoStage.seam.height)
                        .position(x: demoStage.seam.midX - insets.leading, y: demoStage.seam.midY - insets.top)

                    VStack {
                        ExchangeDemoCaption(phase: demoPhase)
                            .padding(.top, max(20, proxy.size.height * 0.05))
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                }
            }
        }
    }

    var body: some View {
        sceneContent
        // The name popover handles its own keyboard. Keep the entire match
        // canvas at its original size so the heart and controls stay in place.
        .ignoresSafeArea(.keyboard, edges: activeMatch == nil ? [] : .bottom)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Keep the light at its largest size at this width while the keyboard resizes the controls.
            if size.width != lightLayoutSize.width || size.height > lightLayoutSize.height {
                lightLayoutSize = size
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.6), trigger: lockPulse)
        .sensoryFeedback(.error, trigger: showsUnderageNotice) { _, shown in shown }
        .sensoryFeedback(.success, trigger: demoStarts)
        .sensoryFeedback(.success, trigger: exchanges)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                profileCreation.persist()
                // The light stops while the app is away; the phones would not.
                cancelDemo()
            } else {
                checkAccess()
                Task { await notifications.refresh() }
                Task { await syncProfile() }
            }
        }
        .task {
            access.updateCompletion(profileCreation.state.completedAt)
            await access.start()
            if automaticallyShowsAccessOnAppear { checkAccess() }
            await notifications.refresh()
            hasLoadedNotifications = true
        }
        .task(id: profileSyncRevision) {
            // Wait until a saved answer has settled, rather than uploading
            // each intermediate selection during editing.
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            await syncProfile()
        }
        .onChange(of: profileCreation.hasDisplayName) { _, hasName in
            if !hasName { showsCode = false }
        }
        .onChange(of: access.hasAccess) { _, allowed in
            if !allowed { checkAccess() }
        }
        .sheet(isPresented: $showsProfilePrivacy) {
            PrivacyConsentView(kind: .profile) { profileCreation.acceptPrivacy(.profile) }
        }
        .sheet(isPresented: $showsCreateAccount, onDismiss: {
            if hasAccount { onAccountCreated() }
        }) {
            NavigationStack {
                SignInPlaceholderView(authService: authService) { session in
                    switch session {
                    case .signedOut: break
                    case .onboarding, .signedIn:
                        hasAccount = true
                        showsCreateAccount = false
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n("Close")) { showsCreateAccount = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showsOverview) {
            ProfileOverviewView(viewModel: profileCreation, locationService: locationService,
                                onUnderage: showUnderageNotice)
        }
        .fullScreenCover(isPresented: $showsAutoMatching) {
            AutoMatchingSetupView(viewModel: profileCreation, locationService: locationService,
                                  serverVerification: photoVerification) {
                showsAutoMatching = false
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showsSavedMatches) {
            SavedMatchesView(store: savedMatches, onOpen: openSavedMatch)
        }
        .fullScreenCover(isPresented: $showsScanner) {
            ProfileCodeScannerView(onScan: finishScanning) { showsScanner = false }
        }
        .onChange(of: canShowScannedMatch && (scannedProfile != nil || codeInbox.pending != nil), initial: true) { _, ready in
            if ready { showScannedMatch() }
        }
        .onChange(of: showsOverview) { _, shown in
            // The code holds the answers themselves, so edits change it.
            if !shown, showsCode { refreshShareCode() }
        }
        .sheet(item: $scoreDetail) { perspective in
            if let activeMatch {
                MatchScoreDetailView(report: activeMatch.report, perspective: perspective,
                                     name: activeMatch.snapshot.name)
            }
        }
        .sheet(isPresented: $showsMatchProfile) {
            if let activeMatch {
                MatchProfileView(match: activeMatch.snapshot)
            }
        }
        .onChange(of: isSharing, initial: true) { _, sharing in
            if sharing {
                exchange.start(profile: profileCreation.state)
            } else {
                exchange.stop()
            }
        }
        .onChange(of: exchange.result) { _, result in
            guard let result, stage == .complete, activeMatch == nil else { return }
            profileCreation.markProfileExchangeUsed()
            exchanges += 1
            present(MatchSnapshot(id: result.id, matchedAt: Date(), you: result.you, them: result.them))
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
                if profileSyncFailed {
                    Button(L10n("Profile backup couldn’t be saved. Tap to retry.")) {
                        Task { await syncProfile() }
                    }
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                }
                if showsCode && profileCreation.state.canShareProfile {
                    ProfileExchangeCard(session: exchange)
                } else {
                    switch profileCreation.state.nextAction {
                    case .name:
                        ProfileNameCard(viewModel: profileCreation)
                    case .privacy:
                        Button(L10n("Read about your privacy")) { showsProfilePrivacy = true }
                            .buttonStyle(GlowButtonStyle())
                    case .explanation:
                        Button(L10n("Show how it works"), action: startDemoMatch)
                            .buttonStyle(GlowButtonStyle())
                        Button(L10n("I fully understand")) { profileCreation.acknowledgeExplanation() }
                            .buttonStyle(QuietButtonStyle())
                    case .matching:
                        matchingEntry
                    }
                }

                if profileCreation.state.nextAction == .matching {
                    // The finished flow: the profile itself, and every match it made.
                    Button(L10n("Adjust profile"), action: adjustProfile)
                        .buttonStyle(GlowButtonStyle())
                    Button(L10n("Saved matches"), action: openSavedMatches)
                        .buttonStyle(QuietButtonStyle())
                } else if profileCreation.state.nextAction != .explanation {
                    Button(L10n("Adjust profile"), action: adjustProfile)
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .padding(.bottom, 18)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                       value: profileCreation.state.nextAction)
            .animation(.easeInOut(duration: 0.3), value: showsCode)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: hasAccount)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: notifications.state)
        }
    }

    private var profileSyncRevision: Data? {
        guard hasAccount else { return nil }
        return try? JSONEncoder().encode(profileCreation.state)
    }

    private func syncProfile() async {
        guard hasAccount, let profileSync else { return }
        do {
            try await profileSync.synchronize()
            profileSyncFailed = false
        } catch {
            if !Task.isCancelled { profileSyncFailed = true }
        }
    }

    @ViewBuilder
    private var matchingEntry: some View {
        if hasAccount, let chatRepository {
            MatchingHubView(repository: chatRepository)
        }
        switch AutoMatchingEntryStep.resolve(hasAccount: hasAccount, notificationState: hasLoadedNotifications ? notifications.state : nil) {
        case .account:
            AccountCreationCard {
                guard !isTransitioning else { return }
                showsCode = false
                showsCreateAccount = true
            }
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: OnboardingTheme.buttonHeight)
        case .notifications:
            Button(L10n("Allow notifications")) {
                Task { await notifications.requestAuthorization() }
            }
            .buttonStyle(GlowButtonStyle())
            .disabled(notifications.isRequesting)
        case .matching:
            AutoMatchingCard(viewModel: profileCreation) {
                guard !isTransitioning else { return }
                showsAutoMatching = true
            }
        }
    }

    // MARK: - Stage changes

    private func openAccess() {
        guard !showsAccess else { return }
        showsCode = false
        withAnimation(AccessScreenMotion.travel(reduceMotion: reduceMotion)) {
            showsAccess = true
        }
    }

    private func closeAccess() {
        guard !access.isBusy else { return }
        withAnimation(AccessScreenMotion.travel(reduceMotion: reduceMotion)) {
            showsAccess = false
            stage = .landing
            lightStage = .landing
        }
    }

    private func continueFromAccess() {
        withAnimation(AccessScreenMotion.travel(reduceMotion: reduceMotion)) {
            showsAccess = false
            if profileCreation.isCompleted {
                stage = .complete
                lightStage = .complete
            }
        }
        if !profileCreation.isCompleted { openOnboarding() }
    }

    private func handleGetStarted() {
        guard !isTransitioning else { return }
        guard profileCreation.isUnderageLocked else {
            if access.isReady && access.hasAccess { openOnboarding() }
            else { openAccess() }
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
        if access.hasAccess { openOnboarding(delay: reduceMotion ? 0 : 0.9) }
        else { openAccess() }
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
        guard profileCreation.state.canShareProfile else {
            if profileCreation.hasDisplayName { showsProfilePrivacy = true }
            return
        }
        guard showsCode || refreshShareCode() else { return }
        withAnimation(.easeInOut(duration: 0.25)) { showsCode.toggle() }
    }

    /// Packs the current answers into the code. False when they don't fit.
    @discardableResult
    private func refreshShareCode() -> Bool {
        guard let link = ProfileCode.url(for: profileCreation.state),
              let matrix = WelcomeLightCode.Matrix(message: link.absoluteString) else { return false }
        shareCode = matrix
        return true
    }

    private func openScanner() {
        guard !isTransitioning, activeMatch == nil, profileCreation.state.canShareProfile else { return }
        showsScanner = true
    }

    private func finishScanning(_ profile: ProfileCreationState) {
        showsScanner = false
        Task {
            // Let the cover finish closing before the match starts.
            try? await Task.sleep(for: .seconds(0.45))
            scannedProfile = profile
        }
    }

    /// The same match an exchange between two phones gives, from the
    /// answers in the other person's code.
    private func showScannedMatch() {
        guard canShowScannedMatch, let them = scannedProfile ?? codeInbox.take() else { return }
        scannedProfile = nil
        profileCreation.markProfileExchangeUsed()
        exchanges += 1
        present(MatchSnapshot(matchedAt: Date(), you: profileCreation.state.sharedCopy(today: .today()), them: them))
    }

    // MARK: - Matches

    /// Plays the explanation: two phones, top to top, and the match that
    /// comes back. With reduced motion only the match itself is shown.
    private func startDemoMatch() {
        guard stage == .complete, lightStage == .complete, profileCreation.state.canShareProfile,
              demoPhase == nil, isDemoPlaying || (activeMatch == nil && !isTransitioning) else { return }
        var generator = SystemRandomNumberGenerator()
        let snapshot: MatchSnapshot
        let replaces = activeMatch != nil
        if isDemoPlaying, let current = activeMatch?.snapshot {
            snapshot = MatchSnapshot(matchedAt: current.matchedAt, you: current.you, them: current.them)
        } else {
            snapshot = DemoMatchGenerator.makeExample(for: profileCreation.state, using: &generator)
        }
        isDemoPlaying = true
        scoreDetail = nil
        showsMatchProfile = false
        showsCode = false
        guard !reduceMotion, WelcomeLightMetalView.isAvailable else {
            demoStarts += 1
            present(snapshot)
            return
        }
        isTransitioning = true
        matchTask?.cancel()
        demoTask?.cancel()
        demoTask = Task {
            func wait(_ seconds: Double) async -> Bool {
                try? await Task.sleep(for: .seconds(seconds))
                return !Task.isCancelled
            }
            withAnimation(ExchangeDemo.shrink) { demoPhase = .apart }
            if replaces {
                // Playing again: the match fades as it does on closing, and
                // the helix returns while the screen becomes a phone.
                withAnimation(.easeOut(duration: 0.3)) {
                    activeMatch = nil
                    matchReveal = .hidden
                    isLightHidden = true
                }
                guard await wait(0.3) else { return }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    lightMatch = nil
                    isLightHidden = false
                }
            }
            guard await wait(ExchangeDemo.apartDuration) else { return }
            withAnimation(ExchangeDemo.turn) { demoPhase = .together }
            guard await wait(ExchangeDemo.togetherDuration) else { return }
            demoPhase = .exchange
            demoStarts += 1
            present(snapshot)
            guard await wait(ExchangeDemo.takeoverDelay) else { return }
            withAnimation(ExchangeDemo.takeover) { demoPhase = .takeover }
            guard await wait(ExchangeDemo.takeoverDuration) else { return }
            demoPhase = nil
        }
    }

    /// Puts the screen back at once. A match that already started simply
    /// carries on at full size.
    private func cancelDemo() {
        guard demoPhase != nil else { return }
        demoTask?.cancel()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            demoPhase = nil
            if activeMatch == nil {
                // Playing again had already let go of the previous match.
                lightMatch = nil
                isLightHidden = false
            }
        }
        if activeMatch == nil {
            isDemoPlaying = false
            isTransitioning = false
        }
    }

    /// New matches send the helix away; saved matches unfold it in place.
    /// The labels follow the selected light timeline.
    private func present(_ snapshot: MatchSnapshot, transition: WelcomeLightMatch.Transition = .newMatch) {
        let report = snapshot.report
        isTransitioning = true
        showsCode = false
        matchReveal = .hidden
        withAnimation(.easeOut(duration: 0.35)) {
            activeMatch = ActiveMatch(snapshot: snapshot, report: report)
        }
        matchStartedAt = Date()
        lightMatch = WelcomeLightMatch.Request(id: snapshot.id, isMatch: report.isMatch, transition: transition)
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
            for (newMatchTime, step) in beats {
                let time = transition.time(newMatchTime, isMatch: report.isMatch)
                if !reduceMotion {
                    try? await Task.sleep(for: .seconds(max(0, time - elapsed)))
                    elapsed = time
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.6)) { matchReveal = step }
            }
            if isDemoPlaying { profileCreation.markDemoCompleted() }
            isTransitioning = false
        }
    }

    private func understandDemo() {
        profileCreation.acknowledgeExplanation()
        closeMatch()
    }

    private func saveMatch(_ snapshot: MatchSnapshot) {
        savedMatches.save(snapshot)
        AccessibilityNotification.Announcement(L10n("Match saved.")).post()
        closeMatch()
    }

    private func renameMatch(to name: String) {
        guard var snapshot = activeMatch?.snapshot, snapshot.rename(to: name) else { return }
        savedMatches.rename(snapshot.id, to: snapshot.name)
        activeMatch = ActiveMatch(snapshot: snapshot, report: snapshot.report)
        AccessibilityNotification.Announcement(L10n("Match name updated.")).post()
    }

    private func deleteMatch(_ snapshot: MatchSnapshot) {
        savedMatches.delete(snapshot.id)
        closeMatch()
    }

    /// The heart fades where it is, and the helix ropes back in from the sides.
    private func closeMatch() {
        guard activeMatch != nil else { return }
        matchTask?.cancel()
        isDemoPlaying = false
        isTransitioning = true
        scoreDetail = nil
        showsMatchProfile = false
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
        guard profileCreation.state.hasUnderstoodExplanation == true,
              !isTransitioning, activeMatch == nil else { return }
        showsCode = false
        showsSavedMatches = true
    }

    private func openSavedMatch(_ snapshot: MatchSnapshot) {
        showsSavedMatches = false
        Task {
            // Let the cover finish closing before the in-place morph starts.
            try? await Task.sleep(for: .seconds(0.45))
            present(snapshot, transition: .savedMatch)
        }
    }

    /// The heart fades where it is; the helix turns in from below the screen
    /// on its renderer's clock, passing behind the controls.
    private func checkAccess() {
        access.updateCompletion(profileCreation.state.completedAt)
        guard access.isReady, access.ledger.effectiveStartedAt != nil, !access.hasAccess else { return }
        cancelDemo()
        showsOverview = false
        showsAutoMatching = false
        showsProfilePrivacy = false
        showsSavedMatches = false
        showsScanner = false
        showsCode = false
        openAccess()
    }

    private func showCompletion() {
        access.updateCompletion(profileCreation.state.completedAt)
        guard access.hasAccess else {
            openAccess()
            return
        }
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

/// Turns the helix into its QR code and back, from the screen's top right.
private struct HelixCodeButton: View {
    static let size: CGFloat = 44

    let showsCode: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: showsCode ? "xmark" : "qrcode")
                .font(.system(size: showsCode ? 16 : 19, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
                .background {
                    Circle().fill(LinearGradient(
                        colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                }
                .overlay {
                    Circle().strokeBorder(OnboardingTheme.accentGradient.opacity(0.45), lineWidth: 1)
                }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsCode ? L10n("Show your helix") : L10n("Show QR code"))
        .accessibilityHint(showsCode ? L10n("Shows your profile DNA.")
                           : L10n("Shows your QR code and looks for phones held against yours."))
    }
}

/// Opens the camera to scan someone else's code, beside `HelixCodeButton`.
private struct CodeScanButton: View {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: HelixCodeButton.size, height: HelixCodeButton.size)
                .background {
                    Circle().fill(LinearGradient(
                        colors: [OnboardingTheme.blue.opacity(0.24), OnboardingTheme.violet.opacity(0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                }
                .overlay {
                    Circle().strokeBorder(OnboardingTheme.accentGradient.opacity(0.45), lineWidth: 1)
                }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n("Scan a code"))
        .accessibilityHint(L10n("Opens the camera to scan someone else’s code."))
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
            access: LifetimeAccessStore(),
            onSignIn: {}
        )
    }
}
