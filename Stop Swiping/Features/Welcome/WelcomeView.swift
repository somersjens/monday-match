import Combine
import SwiftUI
import UIKit

struct WelcomeView: View {
    /// A returning account signed in from the landing controls.
    private let onSignedIn: (RestoredSession) -> Void
    private let onAccountCreated: () -> Void
    private let authService: AuthServicing
    private let profileSync: ProfileCloudSyncing?
    private let chatRepository: SecureChatRepository?
    private let photoVerification: PhotoVerificationService?
    private let automaticallyShowsAccessOnAppear: Bool
    private let onDeleteProfile: (() async throws -> Void)?
    private let onProfileDeleted: () -> Void
    @ObservedObject var access: LifetimeAccessStore
    /// Codes scanned outside the app, with the iPhone's own camera.
    @ObservedObject private var codeInbox: ProfileCodeInbox
    @State private var showsAccess = false

    @StateObject private var profileCreation: ProfileCreationViewModel
    @StateObject private var locationService = LocationService()
    @StateObject private var notifications = NotificationPermissionService()
    /// Plans reminders and routes notification taps; nil in previews and tests.
    @Environment(\.notificationEngine) private var notificationEngine
    @State private var hasAccount: Bool
    /// The landing controls show Apple and Google sign-in instead of Get started.
    @State private var showsSignIn = false
    /// A returning sign-in found no saved profile: the account is new or its
    /// profile was deleted, so the landing says so before anything else.
    @State private var showsNoProfileFound = false
    /// The home screen's account card: closed, opened into sign-in, or confirming it.
    @State private var accountCard = AccountCreationCard.Phase.closed
    @StateObject private var signIn: SignInViewModel
    @State private var hasLoadedNotifications = false
    @State private var profileSyncFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    @State private var showsUnderageNotice = false
    @State private var isTransitioning = false
    @State private var lockPulse = 0
    /// The welcome light's entrance sounds once per screen, like the light.
    @State private var hasPlayedEntrance = false
    /// How many times the personality test has been switched; each switch
    /// plays the next note of the climbing scale, whichever test was chosen.
    @State private var personalitySwitchCount = 0
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
    /// The personality model the helix is shown as; nil shows the helix.
    @State private var personalityTest: PersonalityTest?
    /// The model the helix opens on next time.
    @State private var lastPersonalityTest = PersonalityTest.mbti
    /// Every model's estimate, worked out once when the charts open and again
    /// only when the answers change, never during a frame.
    @State private var personalityResults: [PersonalityTest: PersonalityResult] = [:]
    /// The buttons come back from under the personality card, so they wait
    /// for it to leave instead of fading in through it.
    @State private var returnsFromPersonality = false
    /// The personality estimates opened from a match's settings. The match
    /// rings reweave into the chart while the conversation fades; nil while
    /// the chat shows.
    @State private var matchPersonalityTest: PersonalityTest?
    /// A profile read by the in-app scanner, waiting for its match to be shown.
    @State private var scannedProfile: ProfileCreationState?

    @StateObject private var savedMatches = SavedMatchStore()
    /// The account's active server match and its conversation.
    @StateObject private var liveMatches: LiveMatchCenter
    /// Strikes whose notice was dismissed on this screen, before the server confirms.
    @State private var acknowledgedStrikes = 0
    /// The conversation behind the match on screen, live or demo.
    @State private var activeChat: ChatViewModel?
    /// The heart has turned into the rings and the conversation is open.
    @State private var isChatting = false
    /// Looks for other phones while the profile is being shared.
    @StateObject private var exchange = ProfileExchangeSession()
    @State private var exchanges = 0
    @State private var showsMatchProfile = false
    /// The photo behind a demo match (your own) or an exchanged one (theirs,
    /// when they shared it). A live match's photo comes from `liveMatches`.
    @State private var matchPhoto: UIImage?
    @State private var matchPhotoIsVerified = false
    /// The match shown in place of the home controls.
    @State private var activeMatch: ActiveMatch?
    /// What the light draws. It trails `activeMatch` while the heart fades out.
    @State private var lightMatch: WelcomeLightMatch.Request?
    @State private var matchReveal = MatchReveal.hidden
    @State private var matchStartedAt = Date()
    @State private var matchTask: Task<Void, Never>?
    @State private var scoreDetail: MatchReport.Perspective?
    @State private var showsSavedMatches = false
    /// Set when a cover closes because something else starts at once (a
    /// match, a scanned code), which then brings its own sound.
    @State private var coverHandsOver = false
    @State private var demoStarts = 0
    /// Fake matches alternate between a match and no match.
    @State private var nextFakeMatchSucceeds = true
    @State private var showsProfilePrivacy = false
    /// The light stops only once a cover has finished sliding over it, so it
    /// keeps moving for as long as any of it can still be seen.
    @State private var isLightCovered = false
    @State private var isDemoPlaying = false
    /// Playing the demo again keeps its buttons on the screen itself, not on
    /// the phone that shrinks away.
    @State private var pinsDemoControls = false
    /// The two phones that explain an exchange; nil while this screen is
    /// simply the screen.
    @State private var demoPhase: ExchangeDemo.Phase?
    @State private var demoTask: Task<Void, Never>?
    /// The tallest layout seen at this width. The keyboard shrinks the
    /// layout, but the light stays where it is.
    @State private var lightLayoutSize = CGSize.zero
    /// The personality card's height; on short screens the chart rises
    /// above it instead of running underneath.
    @State private var personalityCardHeight: CGFloat = 0

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
    /// Holding Adjust profile this long shows a made-up match.
    private static let fakeMatchHoldDuration = 3.0

    init(
        profileCreationStore: ProfileCreationStateStoring,
        repository: ProfileRepository?,
        access: LifetimeAccessStore,
        automaticallyShowsAccessOnAppear: Bool = true,
        authService: AuthServicing = MockAuthService(),
        hasAccount: Bool = false,
        profileSync: ProfileCloudSyncing? = nil,
        chatRepository: SecureChatRepository? = nil,
        photoVerification: PhotoVerificationService? = nil,
        codeInbox: ProfileCodeInbox? = nil,
        onDeleteProfile: (() async throws -> Void)? = nil,
        onProfileDeleted: @escaping () -> Void = {},
        onAccountCreated: @escaping () -> Void = {},
        onSignedIn: @escaping (RestoredSession) -> Void = { _ in }
    ) {
        self.codeInbox = codeInbox ?? ProfileCodeInbox()
        self.onSignedIn = onSignedIn
        _signIn = StateObject(wrappedValue: SignInViewModel(authService: authService))
        self.onAccountCreated = onAccountCreated
        self.onDeleteProfile = onDeleteProfile
        self.onProfileDeleted = onProfileDeleted
        self.authService = authService
        self.profileSync = profileSync
        self.chatRepository = chatRepository
        self.photoVerification = photoVerification
        _hasAccount = State(initialValue: hasAccount)
        self.access = access
        self.automaticallyShowsAccessOnAppear = automaticallyShowsAccessOnAppear
        let model = ProfileCreationViewModel(store: profileCreationStore, repository: repository)
        _profileCreation = StateObject(wrappedValue: model)
        _liveMatches = StateObject(wrappedValue: LiveMatchCenter(repository: chatRepository))
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
            && !showsOverview && !showsAutoMatching && !showsSavedMatches && !showsAccess && !showsProfilePrivacy
            && accountCard == .closed
            && !showsScanner
    }

    /// A scanned profile is matched as soon as the home screen is at rest
    /// with a profile of its own to match against.
    private var canShowScannedMatch: Bool {
        stage == .complete && lightStage == .complete && activeMatch == nil && demoPhase == nil && !isTransitioning
            && scenePhase == .active && profileCreation.state.canShareProfile
            && !showsOverview && !showsAutoMatching && !showsSavedMatches && !showsAccess && !showsProfilePrivacy
            && accountCard == .closed
            && !showsScanner
    }

    private var lightForm: WelcomeLightForm {
        switch lightStage {
        case .landing: profileCreation.isUnderageLocked ? .lock : .heart
        case .onboarding: .heart
        case .complete: .helix
        }
    }

    /// The chart the helix is rewoven into, while nothing else needs the light.
    private var personalityResult: PersonalityResult? {
        guard let personalityTest, stage == .complete, lightStage == .complete, activeMatch == nil,
              demoPhase == nil, !showsCode, !showsAccess else { return nil }
        return personalityResults[personalityTest]
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
            // The light keeps the layout of the tallest size seen at this
            // width, so the keyboard never moves it; the controls follow the
            // space that is actually left.
            let layout = WelcomeStageLayout(size: CGSize(width: proxy.size.width, height: layoutHeight))
            let controlsInset = AdaptiveLayout.stageInset(forHeight: proxy.size.height)
            let animationWidth = layout.animationWidth
            let lightCenter = layout.lightCenter
            let lightHeight = layout.lightHeight
            let drawingHeight = layout.drawingHeight
            // Far enough that each waiting backbone starts just past its side
            // of the light's frame.
            let sideEntry = animationWidth / 2 + 24
            let insets = proxy.safeAreaInsets
            let corner = CornerButtonMetrics(size: layout.size)
            let demoStage = ExchangeDemoStage(size: proxy.size, insets: insets,
                                              helixCenter: lightCenter.y, helixUnit: layout.unit)
            let chartLift = personalityLift(layout: layout, height: proxy.size.height, controlsInset: controlsInset,
                                            safeAreaBottom: insets.bottom)
            let lift = personalityResult == nil && matchPersonalityVisual == nil ? 0 : chartLift

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
                                          isPaused: isLightCovered,
                                          framesPerSecond: isOnboarding ? 30 : 60,
                                          helixEntryDistance: sideEntry / max(animationWidth * 0.42, 1)
                                            + WelcomeLightHelix.radius + 0.12,
                                          match: lightMatch,
                                          personality: personalityResult?.visual ?? matchPersonalityVisual)
                        .frame(width: animationWidth, height: drawingHeight)
                        .scaleEffect(showsAccess ? AccessScreenMotion.lightScale(for: animationWidth)
                                     : (isOnboarding ? 0.62 : 1))
                        .opacity(showsAccess ? 1 : (isLightHidden ? 0 : (isOnboarding ? (showsUnderageNotice ? 0.55 : 0.3) : 1)))
                        .position(
                            x: lightCenter.x,
                            y: showsAccess ? controlsInset + AccessScreenMotion.lightCenterY
                                : (isOnboarding ? controlsInset + min(36, layout.animationHeight / 2)
                                   : lightCenter.y - lift)
                        )

                    if !showsAccess && stage == .complete && lightStage == .complete && canShowCode && activeMatch == nil {
                        Button(action: tapHelix) {
                            Color.clear
                                .frame(width: animationWidth * 0.6, height: lightHeight * 0.85)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: lightCenter.x, y: lightCenter.y - lift)
                        .disabled(isTransitioning)
                        .accessibilityLabel(showsCode ? L10n("QR code") : L10n("Your profile DNA"))
                        .accessibilityHint(showsCode || personalityTest != nil
                                           ? L10n("Turns back into your DNA.")
                                           : L10n("Shows your personality estimates."))

                        if let personalityResult {
                            PersonalityChartLabels(result: personalityResult,
                                                   center: CGPoint(x: lightCenter.x, y: lightCenter.y - lift),
                                                   unit: layout.unit)
                                .id(personalityResult.test)
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(.easeInOut(duration: 0.45)
                                        .delay(reduceMotion ? 0 : WelcomeLightPersonality.crossDuration * 0.75)),
                                    removal: .opacity.animation(.easeOut(duration: 0.2))))
                        }

                        // Next to the close button while the code is shown. It
                        // slides out from under that button, so it is drawn
                        // first and animated before it is positioned: a scale
                        // after `position` grows from the middle of the screen.
                        CodeScanButton(size: corner.size, action: openScanner)
                            .scaleEffect(showsCode || reduceMotion ? 1 : 0.6)
                            .offset(x: showsCode || reduceMotion ? 0 : corner.size + corner.spacing)
                            .opacity(showsCode ? 1 : 0)
                            .animation(showsCode ? .spring(duration: 0.42, bounce: 0.18) : .easeIn(duration: 0.18),
                                       value: showsCode)
                            .position(corner.center(slot: 1))
                            .disabled(isTransitioning)
                            .allowsHitTesting(showsCode)
                            .accessibilityHidden(!showsCode)
                            .transition(.opacity)

                        // Fixed to the screen's safe top-right corner.
                        HelixCodeButton(showsCode: showsCode, size: corner.size, action: toggleCode)
                            .position(corner.center(slot: 0))
                            .disabled(isTransitioning)
                            .opacity(demoPhase == nil ? 1 : 0)
                            .transition(.opacity)
                    }

                    if showsAccess {
                        EarlyAccessView(access: access, onContinue: continueFromAccess,
                                        onBack: closeAccess, usesSharedLight: true,
                                        questionnaireProgress: accessProgress)
                            .transition(.asymmetric(insertion: .identity,
                                                    removal: .opacity.animation(.easeOut(duration: 0.2))))
                            .zIndex(2)
                    } else if isOnboarding {
                        ProfileCreationFlowView(
                            viewModel: profileCreation,
                            locationService: locationService,
                            canExitFromFirstStep: true,
                            countdownDeadline: access.questionnaireDeadline,
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
                            frame: MatchStageFrame(center: lightCenter, unit: layout.unit),
                            reveal: matchReveal,
                            isSaved: savedMatches.contains(activeMatch.snapshot.id),
                            lightTransition: lightMatch?.transition ?? .newMatch,
                            lightStartedAt: matchStartedAt,
                            onShowScores: { scoreDetail = $0 },
                            onShowProfile: { showsMatchProfile = true },
                            onRename: renameMatch,
                            onSave: {
                                // Releasing a held Save match after the demo chat opened is no save.
                                guard !isChatting else { return }
                                saveMatch(activeMatch.snapshot)
                            },
                            onClose: closeMatch,
                            onDelete: { deleteMatch(activeMatch.snapshot) },
                            onRestartDemo: restartDemoAction,
                            onUnderstandDemo: understandDemoAction,
                            pinsDemoControls: pinsDemoControls,
                            chat: activeChat,
                            isChatting: isChatting,
                            chatRingsBottom: MatchChatLayout.ringsBottom(unit: layout.unit,
                                                                       lightCenterY: lightCenter.y),
                            controlsBottomInset: controlsInset,
                            onSendMessage: startChat,
                            onStartDemoChat: { startDemoChat(activeMatch.snapshot) },
                            onViewProfile: { showsOverview = true },
                            onShowPersonality: openMatchPersonality,
                            onBreakMatch: breakMatch,
                            onReport: reportMatch,
                            photoCard: activePhotoCard,
                            reportPhoto: activeReportPhoto
                        )
                        // Gives the light to the chart: fades quickly as the rings
                        // start to reweave, and returns once they are nearly back.
                        .animation(MatchPersonalityMotion.chat(returning: matchPersonalityTest == nil,
                                                               reduceMotion: reduceMotion)) {
                            $0.opacity(matchPersonalityTest == nil ? 1 : 0)
                                .blur(radius: matchPersonalityTest != nil && !reduceMotion ? 10 : 0)
                        }
                        .allowsHitTesting(matchPersonalityTest == nil)
                        .transition(.opacity)
                    } else if stage == .complete, demoPhase != nil {
                        // The explanation's phones show only their light.
                        Color.clear
                    } else if stage == .complete, let personalityResult {
                        PersonalityPanel(result: personalityResult,
                                         results: PersonalityTest.allCases.compactMap { personalityResults[$0] },
                                         onSelect: selectPersonalityTest, onClose: closePersonality,
                                         onCardHeightChange: updatePersonalityCardHeight)
                            .padding(.bottom, controlsInset)
                            .transition(.personalitySwap(reduceMotion: reduceMotion))
                    } else if stage == .complete {
                        completionControls
                            .padding(.bottom, controlsInset)
                            .transition(.asymmetric(
                                insertion: returnsFromPersonality
                                    ? .personalitySwap(reduceMotion: reduceMotion)
                                    : reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)),
                                removal: reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom))))
                    } else {
                        landingControls
                            .padding(.bottom, controlsInset)
                            .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
                    }

                    if stage == .complete, activeMatch != nil, let matchPersonalityTest,
                       let result = personalityResults[matchPersonalityTest] {
                        // The chart itself is the match light, rewoven; only its
                        // labels and the card are drawn here, as from the helix.
                        PersonalityChartLabels(result: result,
                                               center: CGPoint(x: lightCenter.x, y: lightCenter.y - chartLift),
                                               unit: layout.unit)
                            .id(result.test)
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.45)
                                    .delay(reduceMotion ? 0 : WelcomeLightPersonality.crossDuration * 0.75)),
                                removal: .opacity.animation(.easeOut(duration: 0.18))))
                            .zIndex(3.1)

                        PersonalityPanel(result: result,
                                         results: PersonalityTest.allCases.compactMap { personalityResults[$0] },
                                         onSelect: selectMatchPersonalityTest, onClose: closeMatchPersonality,
                                         onCardHeightChange: updatePersonalityCardHeight)
                            .padding(.bottom, controlsInset)
                            .transition(.personalitySwap(reduceMotion: reduceMotion))
                            .zIndex(3.2)
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
                        lightCenter: CGPoint(x: insets.leading + lightCenter.x,
                                             y: insets.top + lightCenter.y),
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

                if stage == .complete, pinsDemoControls, isDemoPlaying, !isChatting {
                    // Exactly where the match screen keeps their room.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DemoMatchControls(onRestart: startDemoMatch, onUnderstand: understandDemo)
                    }
                    .padding(.bottom, controlsInset)
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
        // The conversation's composer rides on the keyboard; the light stays put.
        .ignoresSafeArea(.keyboard, edges: activeMatch == nil || isChatting ? [] : .bottom)
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
        .sensoryFeedback(.success, trigger: accountCard) { _, phase in phase == .signedIn }
        .modifier(SoundCues(view: self))
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
        .task(id: pollsLiveMatches) {
            guard pollsLiveMatches else { return }
            await liveMatches.run { [profileCreation] in profileCreation.state }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverDataChanged)) { _ in
            liveMatches.wake()
        }
        .onChange(of: activeMatch == nil) { _, isGone in
            // Leaving the match leaves its personality view too, so the main light runs again.
            if isGone { matchPersonalityTest = nil }
        }
        .onChange(of: liveMatches.match?.id) { old, new in
            // The other person broke the match while it was on screen.
            guard let old, new != old, activeMatch?.snapshot.id == old else { return }
            activeChat?.conversationEnded()
        }
        .task(id: profileSyncRevision) {
            // Wait until a saved answer has settled, rather than uploading
            // each intermediate selection during editing.
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            await syncProfile()
        }
        .onChange(of: profileCreation.state) { _, _ in
            if personalityTest != nil || matchPersonalityTest != nil { refreshPersonalityResults() }
            notificationEngine?.profileChanged()
        }
        .modifier(NotificationWiring(view: self))
        .onChange(of: profileCreation.hasDisplayName) { _, hasName in
            if !hasName { showsCode = false }
        }
        .onChange(of: access.hasAccess) { _, allowed in
            if !allowed { checkAccess() }
        }
        .sheet(isPresented: $showsProfilePrivacy) {
            PrivacyConsentView(kind: .profile) { profileCreation.acceptPrivacy(.profile) }
        }
        .fullScreenCover(isPresented: $showsOverview) {
            profileOverview
        }
        .fullScreenCover(isPresented: $showsAutoMatching) {
            AutoMatchingSetupView(viewModel: profileCreation, locationService: locationService,
                                  serverVerification: photoVerification) {
                showsAutoMatching = false
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showsSavedMatches) {
            SavedMatchesView(store: savedMatches, center: liveMatches, onOpen: openSavedMatch,
                             onOpenBroken: openBrokenMatch)
        }
        .fullScreenCover(isPresented: $showsScanner) {
            ProfileCodeScannerView(onScan: finishScanning) { showsScanner = false }
        }
        .onChange(of: canShowScannedMatch && (scannedProfile != nil || codeInbox.pending != nil), initial: true) { _, ready in
            if ready { showScannedMatch() }
        }
        // With a match you are matched with that one person only: the app
        // opens on it, and straight into the conversation once it has started.
        .onChange(of: canShowScannedMatch && hasAccount && liveMatches.match != nil, initial: true) { _, ready in
            if ready { openLiveMatch() }
        }
        // A demo conversation left open reopens the same way.
        .onChange(of: canShowScannedMatch && !(hasAccount && liveMatches.match != nil), initial: true) { _, ready in
            if ready { resumeDemoChat() }
        }
        .task(id: coversLight) {
            // Presenting slides the cover up over the light; dismissing
            // starts it again straight away, before any of it shows.
            if coversLight {
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
            }
            isLightCovered = coversLight
        }
        .onChange(of: showsOverview) { _, shown in
            // The code holds the answers themselves, so edits change it.
            if !shown, showsCode { refreshShareCode() }
        }
        .alert(moderationTitle, isPresented: showsModerationNotice) {
            Button(L10n("I understand")) {
                acknowledgedStrikes = liveMatches.moderation?.strikes ?? acknowledgedStrikes
                Task { await liveMatches.acknowledgeModeration() }
            }
        } message: {
            Text(moderationMessage)
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
                exchange.start(profile: profileCreation.state, photo: profileCreation.manualMatchingPhoto)
            } else {
                exchange.stop()
            }
        }
        .onChange(of: exchange.result) { _, result in
            guard let result, stage == .complete, activeMatch == nil else { return }
            profileCreation.markProfileExchangeUsed()
            notificationEngine?.recordCompatibilityCheck()
            exchanges += 1
            if let photo = result.photo { MatchPhotoStore.shared.save(photo, for: result.id) }
            present(MatchSnapshot(id: result.id, matchedAt: Date(), you: result.you, them: result.them))
        }
        .onAppear {
            guard lightStage == .complete else { return }
            if !resumeConversationAtLaunch() { waitForHelixEntrance() }
        }
    }

    private var profileOverview: ProfileOverviewView {
        let deletion: (() async throws -> Void)? = onDeleteProfile == nil ? nil : { try await deleteProfile() }
        return ProfileOverviewView(viewModel: profileCreation, locationService: locationService,
                                   onUnderage: showUnderageNotice, onDeleteProfile: deletion)
    }

    private var landingControls: some View {
        VStack {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if showsSignIn && showsNoProfileFound {
                    VStack(spacing: 6) {
                        Text(L10n("No profile found"))
                            .font(.system(.title2, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n("There’s no saved profile for this account. It may have been deleted, or you signed in another way before."))
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .transition(.landingSwap(index: 0, reduceMotion: reduceMotion))

                    Button(L10n("Create a new profile")) { onSignedIn(.onboarding) }
                        .buttonStyle(GlowButtonStyle())
                        .transition(.landingSwap(index: 1, reduceMotion: reduceMotion))

                    Button(L10n("Use another account"), action: useAnotherAccount)
                        .buttonStyle(QuietButtonStyle())
                        .transition(.landingSwap(index: 2, reduceMotion: reduceMotion))
                } else if showsSignIn {
                    VStack(spacing: 6) {
                        Text(L10n("Welcome back"))
                            .font(.system(.title2, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(OnboardingTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n("Sign in to pick up where you left off."))
                            .font(.subheadline)
                            .foregroundStyle(OnboardingTheme.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .transition(.landingSwap(index: 0, reduceMotion: reduceMotion))

                    AccountSignInButtons(viewModel: signIn,
                                         arrival: { .landingSwap(index: $0 + 1, reduceMotion: reduceMotion) },
                                         onAuthenticated: finishLandingSignIn)

                    if let message = signIn.errorMessage {
                        AccountSignInError(message: message)
                            .transition(.onboardingReveal(reduceMotion: reduceMotion))
                    }

                    Button(L10n("Back"), action: closeSignIn)
                        .buttonStyle(QuietButtonStyle())
                        .disabled(signIn.isSigningIn)
                        .transition(.landingSwap(index: 3, reduceMotion: reduceMotion))
                } else {
                    if profileCreation.isUnderageLocked {
                        Label(L10n("Minors not allowed."), systemImage: "lock.fill")
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(OnboardingTheme.secondaryText)
                            .padding(.bottom, 4)
                            .transition(.onboardingReveal(reduceMotion: reduceMotion))
                    }

                    Button(L10n("Get started"), action: handleGetStarted)
                        .buttonStyle(GlowButtonStyle())
                        .transition(.landingSwap(index: 0, reduceMotion: reduceMotion))

                    Button(L10n("I already have an account"), action: openSignIn)
                        .buttonStyle(QuietButtonStyle())
                        .transition(.landingSwap(index: 1, reduceMotion: reduceMotion))
                }
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .controlsBottomPadding()
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                       value: profileCreation.isUnderageLocked)
            .animation(.easeInOut(duration: 0.2), value: signIn.errorMessage)
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
                        matchingEntry(hasAccount: hasAccount)
                    }
                }

                if accountCard != .closed {
                    // Signing in has the controls to itself.
                } else if profileCreation.state.nextAction == .matching {
                    finishedProfileButtons
                } else if profileCreation.state.nextAction != .explanation {
                    Button(L10n("Adjust profile"), action: adjustProfile)
                        .buttonStyle(QuietButtonStyle())
                        .modifier(fakeMatchHold)
                }
            }
            .overlay(alignment: .bottom) {
                if accountCard.isSignedIn { accountHandover }
            }
            .frame(maxWidth: OnboardingTheme.controlWidth)
            .padding(.horizontal, 28)
            .controlsBottomPadding()
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion),
                       value: profileCreation.state.nextAction)
            .animation(.easeInOut(duration: 0.3), value: showsCode)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: hasAccount)
            .animation(Self.accountMotion(reduceMotion: reduceMotion), value: accountCard)
            .animation(OnboardingMotion.resolved(OnboardingMotion.reveal, reduceMotion: reduceMotion), value: notifications.state)
        }
    }

    private var profileSyncRevision: Data? {
        guard hasAccount else { return nil }
        return try? JSONEncoder().encode(profileCreation.state)
    }

    // MARK: - Reports against this account

    private var showsModerationNotice: Binding<Bool> {
        Binding(get: {
            guard hasAccount, let status = liveMatches.moderation else { return false }
            return status.strikes > max(status.strikesSeen, acknowledgedStrikes)
        }, set: { _ in })
    }

    private var moderationTitle: String {
        guard let status = liveMatches.moderation else { return "" }
        if status.banned { return L10n("Your account is banned") }
        if status.isSuspended() { return L10n("Your account is blocked for 7 days") }
        return L10n("You were reported")
    }

    private var moderationMessage: String {
        guard let status = liveMatches.moderation else { return "" }
        if status.banned {
            return L10n("You were reported three times. Your account can no longer match or chat. You can still delete it from your profile.")
        }
        if status.isSuspended(), let until = status.suspendedUntil {
            let date = until.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLocale.current))
            return L10n("You were reported a second time. Until \(date) you can’t match or chat. A third report bans your account.")
        }
        return L10n("Someone you matched with reported you. This is a warning: a second report blocks you for 7 days, a third bans your account.")
    }

    /// The server is asked about matches only while one can exist: with
    /// automatic matching on, or while a match from before is still active.
    private var pollsLiveMatches: Bool {
        hasAccount && scenePhase == .active && chatRepository != nil
            && (profileCreation.state.autoMatching.isEnabled || liveMatches.match != nil)
    }

    private func syncProfile() async {
        guard hasAccount, let profileSync else { return }
        do {
            let uploads = profileSync.completedUploads
            try await profileSync.synchronizeMatchingProfile()
            profileSyncFailed = false
            // Saving searches for a partner on the server: ask once now
            // rather than wait for the match's push.
            if profileSync.completedUploads != uploads { liveMatches.serverMayHaveChanged() }
        } catch {
            if !Task.isCancelled { profileSyncFailed = true }
        }
    }

    /// The finished flow: the profile itself, and every match it made.
    @ViewBuilder
    private var finishedProfileButtons: some View {
        Button(L10n("Adjust profile"), action: adjustProfile)
            .buttonStyle(GlowButtonStyle())
            .modifier(fakeMatchHold)
        Button(L10n("My matches"), action: openSavedMatches)
            .buttonStyle(QuietButtonStyle())
    }

    /// The controls that follow the account, drawn exactly where they will
    /// settle. They rise one after another while the confirmed card sinks,
    /// then the real ones replace them without moving, so nothing jumps.
    private var accountHandover: some View {
        let hasArrived = accountCard == .handover
        return VStack(spacing: 12) {
            matchingEntry(hasAccount: true)
                .landingArrival(hasArrived, index: 0, reduceMotion: reduceMotion)
            Button(L10n("Adjust profile"), action: {})
                .buttonStyle(GlowButtonStyle())
                .landingArrival(hasArrived, index: 1, reduceMotion: reduceMotion)
            Button(L10n("My matches"), action: {})
                .buttonStyle(QuietButtonStyle())
                .landingArrival(hasArrived, index: 2, reduceMotion: reduceMotion)
        }
        .fixedSize(horizontal: false, vertical: true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func matchingEntry(hasAccount: Bool) -> some View {
        if hasAccount, liveMatches.match != nil {
            LiveMatchCard(center: liveMatches, onOpen: openLiveMatch)
        }
        switch AutoMatchingEntryStep.resolve(hasAccount: hasAccount, notificationState: hasLoadedNotifications ? notifications.state : nil) {
        case .account:
            AccountCreationCard(phase: accountCard, signIn: signIn, onToggle: toggleAccountCard,
                                onAuthenticated: finishAccountCreation)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: OnboardingTheme.buttonHeight)
        case .notifications:
            NotificationPermissionCard(isRequesting: notifications.isRequesting) {
                Task { await notifications.requestAuthorization() }
            }
        case .matching:
            AutoMatchingCard(viewModel: profileCreation) {
                guard !isTransitioning else { return }
                showsAutoMatching = true
            }
        }
    }

    /// What the notification engine needs from this screen: the live match
    /// and its conversation, whether the chat is open, the permission, and
    /// the screens notification taps ask for.
    private struct NotificationWiring: ViewModifier {
        let view: WelcomeView

        func body(content: Content) -> some View {
            content
                .onChange(of: view.liveMatchSignal, initial: true) { _, _ in view.reportLiveMatch() }
                .onChange(of: view.isChatting, initial: true) { _, chatting in view.notificationEngine?.isChatOpen = chatting }
                .onChange(of: view.notifications.state) { _, _ in
                    Task { await view.notificationEngine?.refreshPermission(); await view.notificationEngine?.sync() }
                }
                .onReceive(view.notificationEngine?.$pendingDestination.eraseToAnyPublisher()
                           ?? Empty().eraseToAnyPublisher()) { destination in
                    guard let destination else { return }
                    view.open(destination)
                }
        }
    }

    /// Changes whenever anything the engine plans conversation reminders from does.
    fileprivate struct LiveMatchSignal: Equatable {
        let matchID: UUID?
        let messageIDs: [UUID]
        let lastReadAt: Date?
        let unsent: [UUID]
        let history: [UUID]
        let suspended: Bool
    }

    fileprivate var liveMatchSignal: LiveMatchSignal {
        let chat = liveMatches.chat
        let messages = chat?.conversation.messages ?? []
        return LiveMatchSignal(matchID: liveMatches.match?.id, messageIDs: messages.map(\.id),
                               lastReadAt: chat?.lastReadAt,
                               unsent: messages.filter { chat?.isDelivered($0) == false }.map(\.id),
                               history: liveMatches.pastMatches.map(\.id), suspended: isSuspendedFromMatching)
    }

    private var isSuspendedFromMatching: Bool {
        guard let moderation = liveMatches.moderation else { return false }
        return moderation.banned || moderation.isSuspended()
    }

    fileprivate func reportLiveMatch() {
        guard let notificationEngine, hasAccount else { return }
        let match = liveMatches.match
        let chat = liveMatches.chat
        let messages = chat?.conversation.messages ?? []
        notificationEngine.updateLiveMatch(
            match, messages: messages, lastReadAt: chat?.lastReadAt,
            unsentIDs: messages.filter { chat?.isDelivered($0) == false }.map(\.id),
            isConversationLoaded: chat != nil && (match?.lastMessageAt == nil || !messages.isEmpty),
            history: liveMatches.pastMatches, isSuspended: isSuspendedFromMatching)
    }

    /// A tapped notification's screen. Matches and chats open on their own
    /// once nothing covers the home screen; the questionnaire reopens at its
    /// step by itself.
    fileprivate func open(_ destination: NotificationDestination) {
        notificationEngine?.pendingDestination = nil
        guard stage == .complete else { return }
        switch destination {
        case .match, .chat, .profile, .onboarding:
            showsOverview = false
            showsAutoMatching = false
            showsSavedMatches = false
        case .myMatches:
            openSavedMatches()
        case .privacy(.profile):
            if profileCreation.hasDisplayName { showsProfilePrivacy = true }
        case .privacy(.matching), .autoMatching:
            if hasAccount { showsAutoMatching = true }
        case .share:
            if !showsCode { toggleCode() }
        case .notificationSettings:
            showsOverview = true
        }
    }

    /// The sounds that follow the screen's state, kept apart from `body`
    /// so the compiler checks them on their own.
    private struct SoundCues: ViewModifier {
        let view: WelcomeView

        func body(content: Content) -> some View {
            content
                .soundFeedback(.lock, trigger: view.lockPulse)
                .soundFeedback(.rejection, trigger: view.showsUnderageNotice) { _, shown in shown }
                .soundFeedback(.success, trigger: view.accountCard) { _, phase in phase == .signedIn }
                .soundFeedback(.exchange, trigger: view.exchanges)
                // The two phones in the explanation turn toward each other.
                .soundFeedback(.exchange, trigger: view.demoPhase) { _, phase in phase == .together }
                // Screens laid over the light come forward and step back,
                // like the panels on the light itself.
                .onChange(of: view.coversLight) { _, covers in
                    if covers {
                        SoundPlayer.shared.play(.open)
                    } else if view.coverHandsOver {
                        view.coverHandsOver = false
                    } else {
                        SoundPlayer.shared.play(.close)
                    }
                }
                .soundFeedback(trigger: view.showsMatchProfile || view.scoreDetail != nil) { _, shown in
                    shown ? .open : .close
                }
                .onAppear(perform: view.playEntrance)
                .onChange(of: view.ambienceLevel, initial: true) { _, level in
                    SoundPlayer.shared.setAmbience(level)
                }
                .onDisappear { SoundPlayer.shared.setAmbience(0) }
                // A message that arrives while the conversation isn't open.
                // Older unread messages loading at launch stay quiet.
                .onChange(of: view.liveMatches.unreadMessages.last?.id) { _, id in
                    guard id != nil, !view.isChatting, let message = view.liveMatches.unreadMessages.last,
                          Date().timeIntervalSince(message.sentAt) < 30 else { return }
                    SoundPlayer.shared.play(.notification)
                }
        }
    }

    /// The light threads in once when the welcome screen first appears.
    /// With reduced motion the light doesn't travel, so neither does the sound.
    /// A finished profile opens on the helix flying in instead, unless the
    /// app goes straight on to a match, which brings its own sound.
    private func playEntrance() {
        guard !hasPlayedEntrance else { return }
        hasPlayedEntrance = true
        guard !reduceMotion else { return }
        guard skipsEntrance else {
            SoundPlayer.shared.play(.entrance)
            return
        }
        Task {
            await Task.yield()
            guard activeMatch == nil, demoPhase == nil, stage == .complete else { return }
            SoundPlayer.shared.play(.helixArrival)
        }
    }

    /// The bed recedes step by step as the user moves in: full under the
    /// landing page's heart, half behind the access screen, a quarter under
    /// the questionnaire, where the step notes carry the sound. It fades out
    /// as the profile completes, the lock shows, or the light holds still.
    private var ambienceLevel: Float {
        guard scenePhase == .active, !reduceMotion, !profileCreation.isUnderageLocked else { return 0 }
        switch stage {
        case .landing: return showsAccess ? 0.5 : 1
        case .onboarding: return 0.25
        case .complete: return 0
        }
    }

    /// Every switch climbs one note up the scale and starts over after the
    /// top, regardless of which test was picked, carried in on a light breath
    /// as the chart turns over.
    private func playPersonalityNote() {
        personalitySwitchCount += 1
        SoundPlayer.shared.play(.swish)
        SoundPlayer.shared.play(.step(personalitySwitchCount))
    }

    // MARK: - Account

    private static func accountMotion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.6, bounce: 0.12)
    }

    private func openSignIn() {
        guard !isTransitioning else { return }
        signIn.clearError()
        SoundPlayer.shared.play(.open)
        withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) { showsSignIn = true }
    }

    /// A returning account opens on its restored profile. Without one there
    /// is nothing to return to, which the landing explains instead of quietly
    /// starting a new profile.
    private func finishLandingSignIn(_ session: RestoredSession) {
        switch session {
        case .signedOut:
            break
        case .signedIn:
            onSignedIn(session)
        case .onboarding:
            AccessibilityNotification.Announcement(L10n("No profile found")).post()
            withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) { showsNoProfileFound = true }
        }
    }

    /// Signs the empty account out again and offers both providers anew.
    private func useAnotherAccount() {
        Task { try? await authService.signOut() }
        withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) { showsNoProfileFound = false }
    }

    private func closeSignIn() {
        guard !signIn.isSigningIn else { return }
        SoundPlayer.shared.play(.close)
        withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) {
            showsSignIn = false
            signIn.clearError()
        }
    }

    /// The account card's switch slides on and opens sign-in in place;
    /// sliding it back closes it again.
    private func toggleAccountCard() {
        guard !isTransitioning, !signIn.isSigningIn, !accountCard.isSignedIn else { return }
        showsCode = false
        SoundPlayer.shared.play(accountCard == .closed ? .open : .close)
        withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) {
            signIn.clearError()
            accountCard = accountCard == .closed ? .open : .closed
        }
    }

    /// Folds an open account card away before the helix does something else.
    /// False while signing in or confirming, when the card has to stay.
    private func closeAccountCard() -> Bool {
        switch accountCard {
        case .closed:
            return true
        case .open:
            guard !signIn.isSigningIn else { return false }
            SoundPlayer.shared.play(.close)
            withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) {
                signIn.clearError()
                accountCard = .closed
            }
            return true
        case .signedIn, .handover:
            return false
        }
    }

    /// The card confirms the account for a moment where its switch was slid,
    /// then sinks while the next step and the home controls rise in their
    /// final places. Once they have settled they become the real controls in
    /// one unanimated step, so nothing moves.
    private func finishAccountCreation(_ session: RestoredSession) {
        guard session != .signedOut else { return }
        withAnimation(Self.accountMotion(reduceMotion: reduceMotion)) { accountCard = .signedIn }
        AccessibilityNotification.Announcement(L10n("You’re signed in")).post()
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.6 : 1.2))
            // The card and the arriving controls each carry their own motion.
            accountCard = .handover
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 1.0))
            var settled = Transaction()
            settled.disablesAnimations = true
            withTransaction(settled) {
                hasAccount = true
                accountCard = .closed
            }
            onAccountCreated()
        }
    }

    // MARK: - Stage changes

    /// The questionnaire's progress, shown above the plans once it has
    /// started, for instance when the early-adopter time ran out halfway.
    private var accessProgress: Double? {
        guard !profileCreation.isCompleted, !profileCreation.isUnderageLocked else { return nil }
        return EarlyAccessView.questionnaireProgress(profileCreation.state.progress,
                                                     hasStartedEarlyAccess: access.ledger.effectiveStartedAt != nil)
    }

    private func openAccess() {
        guard !showsAccess else { return }
        showsCode = false
        SoundPlayer.shared.play(.open)
        withAnimation(AccessScreenMotion.travel(reduceMotion: reduceMotion)) {
            showsAccess = true
        }
    }

    private func closeAccess() {
        guard !access.isBusy else { return }
        SoundPlayer.shared.play(.close)
        withAnimation(AccessScreenMotion.travel(reduceMotion: reduceMotion)) {
            showsAccess = false
            stage = .landing
            lightStage = .landing
        }
    }

    private func continueFromAccess() {
        // Onboarding sounds its own opening.
        if profileCreation.isCompleted { SoundPlayer.shared.play(.close) }
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
            SoundPlayer.shared.play(.open)
            withAnimation(OnboardingMotion.resolved(OnboardingMotion.stage, reduceMotion: reduceMotion)) {
                stage = .onboarding
                lightStage = .onboarding
            }
            try? await Task.sleep(for: OnboardingMotion.stepLock)
            isTransitioning = false
        }
    }

    /// A screen is presented over the light.
    private var coversLight: Bool {
        showsOverview || showsAutoMatching || showsSavedMatches || showsProfilePrivacy || showsScanner
    }

    private func adjustProfile() {
        guard !isTransitioning, activeMatch == nil else { return }
        showsOverview = true
    }

    /// Everything is erased first; only then does the overview close and the
    /// app return to the first welcome screen.
    private func deleteProfile() async throws {
        guard let onDeleteProfile else { return }
        cancelDemo()
        showsCode = false
        try await onDeleteProfile()
        showsOverview = false
        try? await Task.sleep(for: .seconds(0.45))
        onProfileDeleted()
    }

    /// The helix opens its personality estimates; the code and the charts
    /// turn back into the helix.
    private func tapHelix() {
        guard !isTransitioning, activeMatch == nil, closeAccountCard() else { return }
        if showsCode {
            toggleCode()
        } else if personalityTest != nil {
            closePersonality()
        } else {
            refreshPersonalityResults()
            returnsFromPersonality = false
            SoundPlayer.shared.play(.open)
            withAnimation(.easeInOut(duration: 0.3)) { personalityTest = lastPersonalityTest }
        }
    }

    private func refreshPersonalityResults() {
        let answers = PersonalityAnswers(state: profileCreation.state)
        var results: [PersonalityTest: PersonalityResult] = [:]
        for test in PersonalityTest.allCases {
            results[test] = PersonalityEstimator.result(for: test, answers: answers)
        }
        personalityResults = results
    }

    private func selectPersonalityTest(_ test: PersonalityTest) {
        if test != personalityTest { playPersonalityNote() }
        lastPersonalityTest = test
        withAnimation(.easeInOut(duration: 0.3)) { personalityTest = test }
    }

    private func closePersonality() {
        returnsFromPersonality = true
        SoundPlayer.shared.play(.close)
        withAnimation(.easeInOut(duration: 0.3)) { personalityTest = nil }
    }

    /// The chart the match rings reweave into while the conversation is
    /// set aside for the personality estimates.
    private var matchPersonalityVisual: WelcomeLightPersonality.Visual? {
        guard activeMatch != nil, let matchPersonalityTest else { return nil }
        return personalityResults[matchPersonalityTest]?.visual
    }

    /// How far the chart rises so its lowest labels stay above the card,
    /// never further than the corner buttons allow. Zero on most screens.
    private func personalityLift(layout: WelcomeStageLayout, height: CGFloat, controlsInset: CGFloat,
                                 safeAreaBottom: CGFloat) -> CGFloat {
        guard personalityCardHeight > 0 else { return 0 }
        // The card's own padding, as `controlsBottomPadding()` measures it:
        // lifted off the edge by the inset, it reaches no safe area.
        let padding = OnboardingTheme.controlsBottomPadding(safeAreaBottom: controlsInset > 0 ? 0 : safeAreaBottom)
        let cardTop = height - controlsInset - padding - personalityCardHeight
        let chartBottom = layout.lightCenter.y + 0.95 * layout.unit
        let chartTop = layout.lightCenter.y - layout.unit
        let corner = CornerButtonMetrics(size: layout.size)
        let room = max(0, chartTop - (corner.top + corner.size + 8))
        return min(room, max(0, chartBottom + 12 - cardTop))
    }

    private func updatePersonalityCardHeight(_ height: CGFloat) {
        guard abs(height - personalityCardHeight) > 0.5 else { return }
        withAnimation(.easeInOut(duration: 0.3)) { personalityCardHeight = height }
    }

    private func openMatchPersonality() {
        guard activeMatch != nil, matchPersonalityTest == nil else { return }
        refreshPersonalityResults()
        SoundPlayer.shared.play(.open)
        withAnimation(.easeInOut(duration: 0.3)) { matchPersonalityTest = lastPersonalityTest }
    }

    private func selectMatchPersonalityTest(_ test: PersonalityTest) {
        if test != matchPersonalityTest { playPersonalityNote() }
        lastPersonalityTest = test
        withAnimation(.easeInOut(duration: 0.3)) { matchPersonalityTest = test }
    }

    private func closeMatchPersonality() {
        guard matchPersonalityTest != nil else { return }
        SoundPlayer.shared.play(.close)
        withAnimation(.easeInOut(duration: 0.3)) { matchPersonalityTest = nil }
    }

    private func toggleCode() {
        guard !isTransitioning, activeMatch == nil, closeAccountCard() else { return }
        personalityTest = nil
        guard profileCreation.state.canShareProfile else {
            if profileCreation.hasDisplayName { showsProfilePrivacy = true }
            return
        }
        guard showsCode || refreshShareCode() else { return }
        SoundPlayer.shared.play(showsCode ? .close : .open)
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
        coverHandsOver = true
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
        notificationEngine?.recordCompatibilityCheck()
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
            snapshot = MatchSnapshot(matchedAt: current.matchedAt, you: current.you, them: current.them, isDemo: true)
        } else {
            snapshot = DemoMatchGenerator.makeExample(for: profileCreation.state, using: &generator)
        }
        isDemoPlaying = true
        if replaces { pinsDemoControls = true }
        scoreDetail = nil
        showsMatchProfile = false
        showsCode = false
        personalityTest = nil
        returnsFromPersonality = false
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

    /// Before launch there is nobody to match with: holding Adjust profile
    /// shows a made-up match, alternately a match and no match.
    private var fakeMatchHold: FakeMatchHold {
        FakeMatchHold(duration: Self.fakeMatchHoldDuration, action: startFakeMatch)
    }

    private func startFakeMatch() {
        guard stage == .complete, lightStage == .complete, profileCreation.state.canShareProfile,
              demoPhase == nil, activeMatch == nil, !isTransitioning else { return }
        var generator = SystemRandomNumberGenerator()
        let snapshot = DemoMatchGenerator.makeMatch(for: profileCreation.state,
                                                    shouldMatch: nextFakeMatchSucceeds,
                                                    using: &generator)
        nextFakeMatchSucceeds.toggle()
        scoreDetail = nil
        showsMatchProfile = false
        demoStarts += 1
        present(snapshot)
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
            pinsDemoControls = false
            isTransitioning = false
        }
    }

    /// New matches send the helix away; saved matches unfold it in place.
    /// The labels follow the selected light timeline.
    /// The photo card behind the match on screen; without a photo there is
    /// none, and no button for it. A match the server made shows the other
    /// person while it is active; a demo shows your own card, as a match
    /// would see it; an exchange shows the photo they chose to share.
    private var activePhotoCard: MatchPhotoCard? {
        guard let snapshot = activeMatch?.snapshot else { return nil }
        let today = CalendarDate.today()
        if snapshot.isLive {
            guard !snapshot.isBroken, let live = liveMatches.match, live.id == snapshot.id,
                  let photo = liveMatches.partnerPhoto else { return nil }
            return MatchPhotoCard(name: snapshot.name, age: snapshot.them.age(on: today), photo: photo,
                                  isVerified: live.partnerPhotoVerified,
                                  distanceKilometers: snapshot.distanceKilometers)
        }
        guard let matchPhoto else { return nil }
        if snapshot.isDemo {
            let you = profileCreation.state
            return MatchPhotoCard(name: you.displayName.isEmpty ? L10n("You") : you.displayName,
                                  age: you.age(on: today), photo: matchPhoto,
                                  isVerified: matchPhotoIsVerified,
                                  distanceKilometers: snapshot.distanceKilometers, isOwnPreview: true)
        }
        // Another phone can't prove its photo was verified, so it never says so.
        return MatchPhotoCard(name: snapshot.name, age: snapshot.them.age(on: today), photo: matchPhoto,
                              isVerified: false, distanceKilometers: snapshot.distanceKilometers)
    }

    /// The photo for a report's PDF: the other person's, or your own in the
    /// demo. Unlike the photo card, also after a live match is broken.
    private var activeReportPhoto: UIImage? {
        guard let snapshot = activeMatch?.snapshot else { return nil }
        if snapshot.isLive {
            guard liveMatches.match?.id == snapshot.id else { return nil }
            return liveMatches.partnerPhoto
        }
        return matchPhoto
    }

    /// Reads the photo for a demo or exchanged match once, decoding it off
    /// the main actor. A live match's photo comes from the server instead.
    private func loadMatchPhoto(for snapshot: MatchSnapshot) {
        matchPhoto = nil
        matchPhotoIsVerified = false
        guard !snapshot.isLive else { return }
        let data: Data?
        if snapshot.isDemo, let own = profileCreation.matchCardPhoto {
            matchPhotoIsVerified = own.isVerified
            data = own.imageData
        } else {
            data = snapshot.isDemo ? nil : MatchPhotoStore.shared.photo(for: snapshot.id)
        }
        guard let data else { return }
        let id = snapshot.id
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let image = UIImage(data: data) else { return nil }
                return await image.byPreparingForDisplay() ?? image
            }.value
            guard activeMatch?.snapshot.id == id else { return }
            matchPhoto = image
        }
    }

    private func present(_ snapshot: MatchSnapshot, transition: WelcomeLightMatch.Transition = .newMatch,
                         chatting: Bool = false) {
        let report = snapshot.report
        if activeMatch?.snapshot.id != snapshot.id { loadMatchPhoto(for: snapshot) }
        showsCode = false
        personalityTest = nil
        matchPersonalityTest = nil
        returnsFromPersonality = false
        matchStartedAt = Date()
        if chatting {
            // Back into an open conversation: the helix flows straight into
            // the rings and the messages are already there.
            matchTask?.cancel()
            matchReveal = .controls
            isChatting = true
            SoundPlayer.shared.play(.chatOpen)
            activeMatch = ActiveMatch(snapshot: snapshot, report: report)
            lightMatch = WelcomeLightMatch.Request(id: snapshot.id, isMatch: report.isMatch,
                                                   transition: transition, isChatting: true)
            isTransitioning = false
            return
        }
        isTransitioning = true
        matchReveal = .hidden
        SoundPlayer.shared.play(transition == .savedMatch ? .unfold : (report.isMatch ? .match : .noMatch))
        withAnimation(.easeOut(duration: 0.35)) {
            activeMatch = ActiveMatch(snapshot: snapshot, report: report)
        }
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
        guard isDemoPlaying else { return }
        profileCreation.acknowledgeExplanation()
        if demoPhase != nil {
            // Understood while it plays again: the phones give way at once.
            cancelDemo()
        }
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

    /// A saved match is first kept as broken; a broken or unsaved one goes for good.
    private func deleteMatch(_ snapshot: MatchSnapshot) {
        if savedMatches.contains(snapshot.id) && !snapshot.isBroken {
            savedMatches.markBroken(snapshot.id)
            AccessibilityNotification.Announcement(L10n("Match broken.")).post()
        } else {
            savedMatches.delete(snapshot.id)
        }
        closeMatch()
    }

    /// The heart fades where it is, and the helix ropes back in from the sides.
    private func closeMatch() {
        guard activeMatch != nil else { return }
        OpenDemoChat.clear()
        matchTask?.cancel()
        isDemoPlaying = false
        isTransitioning = true
        scoreDetail = nil
        showsMatchProfile = false
        SoundPlayer.shared.fadeOut(.match, .noMatch, .unfold, .chatOpen)
        // Without motion nothing flies back in; the panel just closes.
        if reduceMotion { SoundPlayer.shared.play(.close) }
        // Photos of matches that weren't kept go with them.
        MatchPhotoStore.shared.prune(keeping: Set(savedMatches.matches.map(\.id)))
        Task {
            withAnimation(.easeOut(duration: 0.3)) {
                pinsDemoControls = false
                activeMatch = nil
                activeChat = nil
                isChatting = false
                matchReveal = .hidden
                if !reduceMotion { isLightHidden = true }
            }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(0.3))
                // The helix ropes back in from the sides.
                SoundPlayer.shared.play(.helixArrival)
            }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                lightMatch = nil
                isLightHidden = false
            }
            waitForHelixEntrance()
        }
    }

    // MARK: - Conversation

    /// The server's match, shown like any other: the first time with the full
    /// arrival, afterwards unfolding in place from the helix.
    private func openLiveMatch() {
        guard !isTransitioning, activeMatch == nil, demoPhase == nil,
              let snapshot = liveMatches.snapshot(fallbackYou: profileCreation.state) else { return }
        let transition: WelcomeLightMatch.Transition = liveMatches.hasBeenSeen(snapshot.id) ? .savedMatch : .newMatch
        liveMatches.markSeen(snapshot.id)
        showsCode = false
        activeChat = liveMatches.chat
        present(snapshot, transition: transition,
                chatting: activeChat != nil && liveMatches.hasStartedChat(snapshot.id))
    }

    /// The heart's tip pulls up into two rings, the light rises under the
    /// header, and the conversation fades in below.
    private func startChat() {
        guard let activeMatch, activeChat != nil, !isChatting else { return }
        matchTask?.cancel()
        matchReveal = .controls
        isTransitioning = false
        scoreDetail = nil
        lightMatch = WelcomeLightMatch.Request(id: activeMatch.snapshot.id, isMatch: activeMatch.report.isMatch,
                                               transition: lightMatch?.transition ?? .newMatch, isChatting: true)
        SoundPlayer.shared.play(.chatOpen)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.3) : .smooth(duration: 1.6)) {
            isChatting = true
        }
        activeChat?.markAllRead()
        if activeChat?.isLive == true { liveMatches.markChatStarted(activeMatch.snapshot.id) }
        // A conversation has no Save match button: talking keeps the match.
        if !activeMatch.snapshot.isBroken { savedMatches.save(activeMatch.snapshot) }
        AccessibilityNotification.Announcement(L10n("Conversation with \(activeMatch.snapshot.name)")).post()
    }

    /// Before launch: a made-up conversation that answers every message.
    private func startDemoChat(_ snapshot: MatchSnapshot) {
        // Only a heart can become the rings; a broken one has nothing to say.
        guard !isChatting, snapshot.report.isMatch,
              activeChat == nil || !(activeChat?.isLive ?? false) else { return }
        let chat = ChatViewModel.demo(matchID: snapshot.id, name: snapshot.name)
        keepDemoChat(chat, for: snapshot)
        activeChat = chat
        startChat()
    }

    /// Saves the demo conversation as it grows, until the match closes.
    private func keepDemoChat(_ chat: ChatViewModel, for snapshot: MatchSnapshot) {
        var open = OpenDemoChat(match: snapshot, conversation: chat.conversation)
        open.save()
        chat.onConversationChange = { conversation in
            open.conversation = conversation
            open.save()
        }
    }

    /// The app was closed in a conversation: it opens in it again with the
    /// rings already formed, instead of letting the helix fly in first and
    /// turning that into the rings. A match whose chat hasn't started still
    /// unfolds from the helix once it has arrived.
    private func resumeConversationAtLaunch() -> Bool {
        guard stage == .complete, activeMatch == nil, demoPhase == nil, !showsAccess,
              profileCreation.state.canShareProfile else { return false }
        if hasAccount, let match = liveMatches.match {
            guard liveMatches.hasStartedChat(match.id) else { return false }
            openLiveMatch()
        } else {
            resumeDemoChat()
        }
        return activeMatch != nil
    }

    /// Back into the demo conversation the app was closed on.
    private func resumeDemoChat() {
        guard activeMatch == nil, let open = OpenDemoChat.load() else { return }
        let chat = ChatViewModel.demo(resuming: open.conversation)
        keepDemoChat(chat, for: open.match)
        activeChat = chat
        present(open.match, transition: .savedMatch, chatting: true)
    }

    /// Ends the match for both people; a demo simply closes.
    private func breakMatch() {
        guard let activeMatch else { return }
        if let chat = activeChat, chat.isLive {
            chat.endMatch()
            liveMatches.forget()
        }
        // It stays in My matches as broken.
        savedMatches.markBroken(activeMatch.snapshot.id)
        AccessibilityNotification.Announcement(L10n("Match broken.")).post()
        closeMatch()
    }

    private func reportMatch(_ reason: ReportReason, details: String, alsoBreak: Bool) {
        activeChat?.submitReport(reason: reason, details: details, endMatch: alsoBreak)
        AccessibilityNotification.Announcement(L10n("Thanks. Your report was sent.")).post()
        if alsoBreak {
            if activeChat?.isLive == true { liveMatches.forget() }
            if let id = activeMatch?.snapshot.id { savedMatches.markBroken(id) }
            closeMatch()
        }
    }

    private func openSavedMatches() {
        guard profileCreation.state.hasUnderstoodExplanation == true,
              !isTransitioning, activeMatch == nil else { return }
        showsCode = false
        showsSavedMatches = true
        Task { await liveMatches.loadHistory() }
    }

    /// A broken automatic match: its heart with "Match" struck through, and
    /// its conversation where a non-match would list its reasons.
    private func openBrokenMatch(_ match: CloudChatMatch) {
        coverHandsOver = showsSavedMatches
        showsSavedMatches = false
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            guard activeMatch == nil else { return }
            activeChat = liveMatches.historyChat(for: match)
            present(liveMatches.snapshot(of: match, fallbackYou: profileCreation.state), transition: .savedMatch)
        }
    }

    private func openSavedMatch(_ snapshot: MatchSnapshot) {
        // A server match opens with its conversation, wherever it stands.
        if snapshot.isLive {
            if liveMatches.match?.id == snapshot.id {
                coverHandsOver = true
                showsSavedMatches = false
                Task {
                    try? await Task.sleep(for: .seconds(0.45))
                    openLiveMatch()
                }
                return
            }
            if let past = liveMatches.pastMatches.first(where: { $0.id == snapshot.id }) {
                openBrokenMatch(past)
                return
            }
        }
        coverHandsOver = true
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
        SoundPlayer.shared.play(.complete)
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
        SoundPlayer.shared.play(.close)
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

/// Size and place of the round buttons in the home screen's top right, for
/// a safe-area size. Every iPhone keeps 44 pt; wider screens (iPhone Duo,
/// iPad) grow them, their margins and their spacing together, up to 56 pt,
/// so they keep their weight next to a larger light.
struct CornerButtonMetrics: Equatable {
    let containerWidth: CGFloat
    let size: CGFloat
    /// Below the safe top edge.
    let top: CGFloat
    let trailing: CGFloat
    /// Between two buttons side by side.
    let spacing: CGFloat

    init(size container: CGSize) {
        containerWidth = container.width
        let shortSide = min(container.width, container.height)
        let scale = min(max(shortSide / 440, 1), 56 / 44)
        size = (44 * scale).rounded()
        top = (14 * scale).rounded()
        spacing = (10 * scale).rounded()
        // While the bottom controls span the width, the right edge lines up
        // with theirs; beside a centred column it keeps to the corner.
        let controlsSpanWidth = container.width <= OnboardingTheme.controlWidth + 2 * 28
        trailing = controlsSpanWidth ? 28 : (28 * scale).rounded()
    }

    /// Slot 0 is the corner; slot 1 sits to its left.
    func center(slot: Int) -> CGPoint {
        CGPoint(x: containerWidth - trailing - size / 2 - CGFloat(slot) * (size + spacing),
                y: top + size / 2)
    }
}

/// Turns the helix into its QR code and back, from the screen's top right.
private struct HelixCodeButton: View {
    let showsCode: Bool
    var size: CGFloat = 44
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: showsCode ? "xmark" : "qrcode")
                .font(.system(size: size * (showsCode ? 16 : 19) / 44, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
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
    var size: CGFloat = 44
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: size * 19 / 44, weight: .semibold))
                .foregroundStyle(OnboardingTheme.accentGradient)
                .frame(width: size, height: size)
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
    @ObservedObject var access: LifetimeAccessStore
    let onComplete: () -> Void
    let onUnderage: () -> Void

    @StateObject private var viewModel: ProfileCreationViewModel
    @StateObject private var locationService = LocationService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsUnderageNotice = false

    init(
        store: ProfileCreationStateStoring,
        repository: ProfileRepository?,
        access: LifetimeAccessStore,
        onComplete: @escaping () -> Void,
        onUnderage: @escaping () -> Void
    ) {
        self.access = access
        self.onComplete = onComplete
        self.onUnderage = onUnderage
        _viewModel = StateObject(wrappedValue: ProfileCreationViewModel(store: store, repository: repository))
    }

    var body: some View {
        GeometryReader { proxy in
            // The same faded light as the questionnaire on the welcome screen.
            let layout = WelcomeStageLayout(size: proxy.size)
            ZStack {
                OnboardingTheme.background
                    .ignoresSafeArea()

                WelcomeLightAnimation()
                    .frame(width: layout.animationWidth, height: layout.drawingHeight)
                    .scaleEffect(0.62)
                    .opacity(0.3)
                    .position(x: proxy.size.width / 2, y: layout.stageTop + min(36, layout.animationHeight / 2))

                ProfileCreationFlowView(
                    viewModel: viewModel,
                    locationService: locationService,
                    canExitFromFirstStep: false,
                    countdownDeadline: access.questionnaireDeadline,
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
        .soundFeedback(.rejection, trigger: showsUnderageNotice) { _, shown in shown }
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
            access: LifetimeAccessStore()
        )
    }
}

/// Runs `action` after the button is held for `duration`, without taking
/// over the button's own tap.
private struct FakeMatchHold: ViewModifier {
    let duration: Double
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: duration)
                    .onEnded { _ in action() }
            )
            .accessibilityAction(named: L10n("Start a demo match"), action)
    }
}

/// How the conversation makes way for the personality charts opened from a
/// match's settings. The rings take about 1.6 s to reweave either way.
private enum MatchPersonalityMotion {
    static func chat(returning: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        // Out before the rings have moved far; back once the chart has mostly
        // rewound, so its strands never run through the messages.
        return returning ? .easeInOut(duration: 0.5).delay(0.65) : .easeOut(duration: 0.3)
    }
}
