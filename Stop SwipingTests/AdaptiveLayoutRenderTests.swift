import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

/// Renders the main screens at every screen class the app runs on: small and
/// large iPhones, iPhone Duo folded and unfolded, and iPad in each
/// orientation and in Split View. Run it on the largest iPad simulator so
/// every size fits; the images land in `ADAPTIVE_RENDER_DIR` when it is set.
@MainActor
final class AdaptiveLayoutRenderTests: XCTestCase {
    struct Device {
        let name: String
        let size: CGSize
        let insets: UIEdgeInsets

        init(_ name: String, _ width: CGFloat, _ height: CGFloat, top: CGFloat, bottom: CGFloat) {
            self.name = name
            size = CGSize(width: width, height: height)
            insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
    }

    static let devices: [Device] = [
        Device("a-se", 375, 667, top: 20, bottom: 0),
        Device("b-mini", 375, 812, top: 50, bottom: 34),
        Device("c-17pro", 402, 874, top: 62, bottom: 34),
        Device("d-promax", 440, 956, top: 62, bottom: 34),
        Device("e-duo-folded", 466, 678, top: 44, bottom: 20),
        Device("f-duo-open", 626, 890, top: 32, bottom: 20),
        Device("g-ipad-split", 504, 820, top: 24, bottom: 20),
        Device("h-ipad-mini", 744, 1133, top: 24, bottom: 20),
        Device("i-ipad11-land", 1180, 820, top: 24, bottom: 20),
        Device("j-ipad13", 1032, 1376, top: 24, bottom: 20),
        Device("k-ipad13-land", 1376, 1032, top: 24, bottom: 20)
    ]

    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    func testRenderWelcomeScreens() async throws {
        for device in Self.devices {
            try await render(WelcomeView(profileCreationStore: InMemoryProfileCreationStore(), repository: nil,
                                         access: await Self.access()),
                             screen: "welcome-landing", device: device, guide: Self.stage(device))
            try await render(WelcomeView(profileCreationStore: InMemoryProfileCreationStore(state: Self.completedState()),
                                         repository: nil, access: await Self.access()),
                             screen: "welcome-home", device: device, guide: Self.stage(device))
        }
    }

    func testRenderOnboardingSteps() async throws {
        for device in Self.devices {
            for step in [ProfileCreationStep.dateOfBirth, .height, .languages, .texting] {
                var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 12), applicationLanguage: "en")
                state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
                state.currentStep = step
                let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
                try await render(
                    ProfileCreationFlowView(viewModel: model, locationService: LocationService(),
                                            canExitFromFirstStep: true, onExit: {}, onUnderage: {}, onComplete: {})
                        .background(OnboardingTheme.background),
                    screen: "onboarding-\(step)", device: device)
            }
        }
    }

    /// A question opened from the profile overview: no step dots, and the
    /// checkmark where the overview has its own.
    func testRenderProfileEditor() async throws {
        for device in Self.devices {
            for step in [ProfileCreationStep.height, .languages, .texting] {
                let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: Self.completedState()),
                                                     repository: nil)
                model.beginEditing(step)
                try await render(
                    ProfileCreationFlowView(viewModel: model, locationService: LocationService(),
                                            canExitFromFirstStep: true, onExit: {}, onUnderage: {}, onComplete: {})
                        .background(OnboardingTheme.background),
                    screen: "editor-\(step)", device: device)
            }
        }
    }

    /// The report notices on the home screen, the objection screen and the
    /// administrator's list, in Dutch (the copy the person sees first).
    func testRenderObjectionScreens() async throws {
        AppLanguageSettings.shared.language = .dutch
        defer { AppLanguageSettings.shared.language = .english }
        let report = ModerationStatus.LatestReport(id: UUID(), reason: "underage", objection: nil)
        let warning = ModerationStatus(strikes: 1, strikesSeen: 0, suspendedUntil: nil, banned: false, latestReport: report)
        let blocked = ModerationStatus(strikes: 2, strikesSeen: 1, suspendedUntil: Date().addingTimeInterval(5 * 86_400),
                                       banned: false, latestReport: .init(id: UUID(), reason: "harassment", objection: .pending))
        let decided = ModerationStatus.ObjectionResult(id: UUID(), decision: .approved, reason: "spam")
        let cards = VStack(spacing: 12) {
            ModerationNoticeCard(notice: ModerationCopy.strike(warning))
            Button(L10n("Understood")) {}.buttonStyle(GlowButtonStyle())
            Button(L10n("Object")) {}.buttonStyle(QuietButtonStyle())
            ModerationNoticeCard(notice: ModerationCopy.result(decided))
            ModerationNoticeCard(notice: ModerationCopy.reportSent(name: "Anna", reason: .harassment, endedMatch: true))
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingTheme.background)
        // Once read: what still holds, in the automatic matching card's place.
        let statuses = VStack(spacing: 12) {
            ModerationStatusCard(status: ModerationCopy.status(blocked), onObject: {})
            ModerationStatusCard(status: ModerationCopy.status(
                ModerationStatus(strikes: 2, strikesSeen: 2, suspendedUntil: Date().addingTimeInterval(5 * 86_400),
                                 banned: false, latestReport: report)), onObject: {})
            ModerationStatusCard(status: ModerationCopy.status(
                ModerationStatus(strikes: 1, strikesSeen: 1, suspendedUntil: nil, banned: false,
                                 latestReport: .init(id: UUID(), reason: "spam", objection: .pending))), onObject: {})
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OnboardingTheme.background)
        let admin = AdminObjectionsView(load: { [try Self.sampleObjection()] }, decide: { _, _, _ in },
                                        loadReviews: { [try Self.sampleReview()] })
        let objection = ReportObjectionSheet(status: warning, report: report, displayName: "Anna",
                                             birthDate: .init(year: 1974, month: 8, day: 12)) { _, _ in }
        let ageCheck = ReportObjectionSheet(status: warning,
                                            report: .init(id: UUID(), reason: "underage", objection: nil),
                                            displayName: "Anna", birthDate: .init(year: 1974, month: 8, day: 12)) { _, _ in }
        let manualReview = ReportObjectionSheet(status: warning,
                                                report: .init(id: UUID(), reason: "underage", objection: nil),
                                                displayName: "Anna", birthDate: .init(year: 1974, month: 8, day: 12),
                                                writesInstead: true, documentPhoto: Self.sampleDocument()) { _, _ in }
        let manualReviewEmpty = ReportObjectionSheet(status: warning,
                                                     report: .init(id: UUID(), reason: "underage", objection: nil),
                                                     displayName: "Anna", birthDate: .init(year: 1974, month: 8, day: 12),
                                                     writesInstead: true) { _, _ in }
        for device in Self.devices.prefix(4) {
            try await render(cards, screen: "objection-cards", device: device)
            try await render(statuses, screen: "objection-status", device: device)
            try await render(objection, screen: "objection-sheet", device: device)
            try await render(ageCheck, screen: "objection-age-check", device: device)
            try await render(manualReview, screen: "objection-age-manual", device: device)
            try await render(manualReviewEmpty, screen: "objection-age-manual-empty", device: device)
            for (name, phase, outcome) in Self.idScanStates {
                let scan = IDDocumentScanScreen(phase: phase, outcome: outcome, needsCameraPermission: false,
                                                onCancel: {}, onRetry: {}, onSettings: {}) {
                    LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
                }
                try await render(scan, screen: "id-scan-\(name)", device: device)
            }
            try await render(admin, screen: "objection-admin", device: device)
        }
    }

    /// Every report state as the home screen's bottom shows it, three phones
    /// side by side: a notice with its own buttons, or a status card above
    /// the usual profile buttons.
    func testRenderModerationHomeStates() async throws {
        let report = ModerationStatus.LatestReport(id: UUID(), reason: "harassment", objection: nil)
        let soon = Date().addingTimeInterval(5 * 86_400)
        func status(_ s: ModerationStatus) -> ModerationNotice { ModerationCopy.status(s) }
        let warning = ModerationStatus(strikes: 1, strikesSeen: 0, suspendedUntil: nil, banned: false, latestReport: report)
        let blocked = ModerationStatus(strikes: 2, strikesSeen: 1, suspendedUntil: soon, banned: false, latestReport: report)
        let banned = ModerationStatus(strikes: 3, strikesSeen: 2, suspendedUntil: nil, banned: true, banReason: .strikes,
                                      latestReport: report)
        let age = ModerationStatus.AgeCheck(id: UUID(), objection: nil)
        let screens: [(String, [AnyView])] = [
            ("home-moderation-1", [
                Self.notice(ModerationCopy.strike(warning)),
                Self.notice(ModerationCopy.strike(blocked)),
                Self.notice(ModerationCopy.strike(banned)),
            ]),
            ("home-moderation-2", [
                Self.notice(ModerationCopy.ageCheck()),
                Self.statusCard(status(ModerationStatus(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: false,
                                                        ageCheck: .init(id: age.id, objection: .pending), ageLocked: true))),
                Self.statusCard(status(ModerationStatus(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: false,
                                                        ageCheck: .init(id: age.id, objection: .rejected), ageLocked: true))),
            ]),
            ("home-moderation-3", [
                Self.statusCard(status(ModerationStatus(strikes: 1, strikesSeen: 1, suspendedUntil: nil, banned: false,
                                                        latestReport: .init(id: UUID(), reason: "spam", objection: .pending)))),
                Self.statusCard(status(ModerationStatus(strikes: 2, strikesSeen: 2, suspendedUntil: soon, banned: false,
                                                        latestReport: report))),
                Self.statusCard(status(ModerationStatus(strikes: 0, strikesSeen: 0, suspendedUntil: nil, banned: true,
                                                        banReason: .device))),
            ]),
            ("home-moderation-4", [
                Self.notice(ModerationCopy.result(.init(id: UUID(), decision: .approved, reason: "spam"))),
                Self.notice(ModerationCopy.result(.init(id: UUID(), decision: .approved, reason: "underage"))),
                Self.notice(ModerationCopy.reportSent(name: "Anna", reason: .harassment, endedMatch: true)),
            ]),
        ]
        let phone = Self.devices[2]
        let canvas = Device("three", phone.size.width * 3, phone.size.height, top: phone.insets.top, bottom: phone.insets.bottom)
        for (name, states) in screens {
            let view = HStack(spacing: 0) {
                ForEach(states.indices, id: \.self) { index in
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        states[index]
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(width: phone.size.width)
                    .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.15)).frame(width: 1) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OnboardingTheme.background)
            try await render(view, screen: name, device: canvas)
        }
    }

    /// A notice and the buttons that take the profile buttons' place.
    /// The live document scan in each of its states.
    static let idScanStates: [(String, IDDocumentScanPhase, IDDocumentScanOutcome?)] = [
        ("searching", .searching, nil),
        ("hold-still", .holdStill, nil),
        ("read", .searching, .read(MachineReadableZone(documentCode: "P", initials: ["A"],
                                                        birthDate: .init(year: 1974, month: 8, day: 12),
                                                        expiryDate: nil, checkDigitsValid: true))),
        ("failed", .searching, .failed(L10n("The lines of <<< couldn’t be read. Make sure they’re sharp, well lit and free of glare, then try again."))),
    ]

    /// A stand-in photo of a document: a pale card with lines on it.
    static func sampleDocument() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 856, height: 540)).image { context in
            UIColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 856, height: 540))
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 60, width: 220, height: 280))
            for row in 0..<6 { context.fill(CGRect(x: 300, y: 70 + row * 42, width: 460 - row * 30, height: 16)) }
            for row in 0..<3 { context.fill(CGRect(x: 40, y: 400 + row * 40, width: 776, height: 18)) }
        }
    }

    private static func notice(_ notice: ModerationNotice) -> AnyView {
        AnyView(VStack(spacing: 12) {
            ModerationNoticeCard(notice: notice)
            if notice.kind == .ageCheck {
                Button(L10n("Confirm age")) {}.buttonStyle(GlowButtonStyle())
            } else {
                Button(L10n("Understood")) {}.buttonStyle(GlowButtonStyle())
                if notice.canObject {
                    Button(L10n("Object")) {}.buttonStyle(QuietButtonStyle())
                    ModerationWarning(text: L10n("An unjustified objection can lead to the immediate termination of your account."))
                }
            }
        })
    }

    /// A status in the automatic matching card's place, above the profile buttons.
    private static func statusCard(_ status: ModerationNotice) -> AnyView {
        AnyView(VStack(spacing: 12) {
            ModerationStatusCard(status: status, onObject: {})
            Button(L10n("Adjust profile")) {}.buttonStyle(GlowButtonStyle())
            Button(L10n("My matches")) {}.buttonStyle(QuietButtonStyle())
        })
    }

    static func sampleReview() throws -> AdminReview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdminReview.self, from: Data("""
        {"id":"\(UUID())","reason":"offlineBehavior","details":"Stond onaangekondigd voor mijn deur.",
         "created_at":"2026-11-20T09:00:00Z","ended_match":true,"is_demo":false,"display_name":"Bram","strike":1,
         "auto_decides_at":"2026-11-27T09:00:00Z"}
        """.utf8))
    }

    static func sampleObjection() throws -> AdminObjection {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AdminObjection.self, from: Data("""
        {"id":"\(UUID())","created_at":"2026-11-20T11:00:00Z","message":"Ik ben 26, zie mijn paspoort.",
         "display_name":"Anna","age_proven_before":true,
         "id_check":{"initial":"A","birth_date":"1974-08-12","adult":true,"expired":false,"check_digits":true,
                     "profile_initial":"A","profile_birth_date":"1974-08-12","initial_matches":true,"birth_date_matches":true},
         "report":{"id":"\(UUID())","reason":"underage","details":"Zei dat ze 16 is.","created_at":"2026-11-19T20:00:00Z",
                   "ended_match":true,"strike":2,
                   "chat_copy":[{"from":"reporter","at":"2026-11-19T19:58:00Z","text":"Hoe oud ben je eigenlijk?"},
                                {"from":"reported","at":"2026-11-19T19:59:00Z","text":"Haha raad maar"}]}}
        """.utf8))
    }

    func testRenderSecondaryScreens() async throws {
        for device in Self.devices {
            let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: Self.completedState()),
                                                 repository: nil)
            try await render(ProfileOverviewView(viewModel: model, locationService: LocationService(), onUnderage: {}),
                             screen: "overview", device: device)
            try await render(AutoMatchingSetupView(viewModel: model, locationService: LocationService(), onFinish: {}),
                             screen: "automatching", device: device)
            for verified in [false, true] {
                try await render(AutoMatchingSetupView(viewModel: Self.photoModel(verified: verified),
                                                       locationService: LocationService(),
                                                       startsOnPhotoStep: true, onFinish: {}),
                                 screen: verified ? "automatching-photo-verified" : "automatching-photo", device: device)
            }
            try await render(AutoMatchingSetupView(viewModel: Self.photoModel(verified: true),
                                                   locationService: LocationService(),
                                                   startsOnPhotoStep: true, asksToRemovePhoto: true, onFinish: {}),
                             screen: "automatching-photo-remove", device: device)
            let noPhoto = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: Self.completedState()),
                                                   repository: InMemoryProfileRepository())
            try await render(AutoMatchingSetupView(viewModel: noPhoto, locationService: LocationService(),
                                                   startsOnPhotoStep: true, onFinish: {}),
                             screen: "automatching-no-photo", device: device)
            try await render(EarlyAccessView(access: await Self.access(), onContinue: {}),
                             screen: "early-access", device: device)
            try await render(NavigationStack { HowItWorksView(onContinue: {}) },
                             screen: "how-it-works", device: device)
            try await render(PrivacyConsentView(kind: .profile, onAccept: {}),
                             screen: "privacy", device: device)
            try await render(FaceVerificationScreen(snapshot: FaceScanSnapshot(phase: .circling, collectedSectors: [0, 1, 2],
                                                                                targetSector: 3),
                                                    outcome: nil, needsCameraPermission: false,
                                                    onCancel: {}, onRetry: {}, onSettings: {}, onDone: {}) { Color.black },
                             screen: "photo-verification-scan", device: device)
            try await render(FaceVerificationScreen(snapshot: FaceScanSnapshot(phase: .circling,
                                                                                collectedSectors: Set(0..<FaceCircleChallenge.sectorCount),
                                                                                targetSector: nil),
                                                    outcome: .match, needsCameraPermission: false,
                                                    onCancel: {}, onRetry: {}, onSettings: {}, onDone: {}) { Color.black },
                             screen: "photo-verification-match", device: device)
            try await render(NavigationStack {
                SignInPlaceholderView(authService: MockAuthService(), onAuthenticated: { _ in })
            }, screen: "sign-in", device: device)
        }
    }

    func testRenderMatchScreens() async throws {
        for device in Self.devices {
            let state = Self.completedState()
            var rng = SystemRandomNumberGenerator()
            let match = DemoMatchGenerator.makeMatch(for: state, shouldMatch: true, using: &rng)
            let chat = ChatViewModel(conversation: ChatConversation(matchID: match.id, participantName: match.name, messages: [
                ChatMessage(sender: .currentUser, text: "Hey! Coffee this weekend?", sentAt: Date().addingTimeInterval(-7200)),
                ChatMessage(sender: .match, text: "Sounds good, Saturday?", sentAt: Date().addingTimeInterval(-7000))
            ]))
            let layout = Self.stage(device)
            for (name, chatting) in [("match", false), ("chat", true)] {
                try await render(
                    MatchResultOverlay(
                        match: match, report: match.report,
                        frame: MatchStageFrame(center: layout.lightCenter, unit: layout.unit),
                        reveal: .controls, isSaved: false,
                        onShowScores: { _ in }, onShowProfile: {}, onRename: { _ in },
                        onSave: {}, onClose: {}, onDelete: {},
                        chat: chatting ? chat : nil, isChatting: chatting,
                        chatRingsBottom: MatchChatLayout.ringsBottom(unit: layout.unit, lightCenterY: layout.lightCenter.y),
                        controlsBottomInset: layout.stageTop
                    ).background(OnboardingTheme.background),
                    screen: name, device: device, guide: layout)
            }
            let results = PersonalityTest.allCases.compactMap {
                PersonalityEstimator.result(for: $0, answers: PersonalityAnswers(state: state))
            }
            try await render(
                ZStack {
                    PersonalityChartLabels(result: results[0], center: layout.lightCenter, unit: layout.unit)
                    PersonalityPanel(result: results[0], results: results, onSelect: { _ in }, onClose: {})
                        .padding(.bottom, layout.stageTop)
                }.background(OnboardingTheme.background),
                screen: "personality", device: device, guide: layout)
            let store = SavedMatchStore(defaults: UserDefaults(suiteName: "adaptive-\(UUID())")!)
            store.save(match)
            try await render(SavedMatchesView(store: store, center: LiveMatchCenter(repository: nil), onOpen: { _ in }),
                             screen: "saved-matches", device: device)
            let scored = Self.scoredMatch()
            try await render(MatchScoreDetailView(report: scored.report, mode: .together, name: scored.name),
                             screen: "score-detail", device: device)
            try await render(MatchScoreDetailView(report: scored.report, mode: .yours, name: scored.name),
                             screen: "score-detail-yours", device: device)
        }
    }

    // MARK: - Fixtures

    static func completedState() -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        state.completedAt = Date()
        state.displayName = "Alex"
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.gender = .man
        state.partnerGenders = [.woman]
        state.profilePrivacyConsent = .init(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: "en")
        state.hasUnderstoodExplanation = true
        return state
    }

    /// A match with every question answered, some answers far apart, so the
    /// score sheet shows strong and weak categories side by side.
    static func scoredMatch() -> MatchSnapshot {
        var you = completedState()
        for (index, question) in CompatibilityScaleQuestion.all.enumerated() {
            let value = 1 + index % 5
            you.lifestyle[question] = CompatibilityScaleAnswer(own: value, partner: value, isPartnerCustomized: true,
                                                               importance: 1 + (index * 2) % 5)
        }
        var rng = SystemRandomNumberGenerator()
        var them = DemoMatchGenerator.makeMatch(for: you, shouldMatch: true, using: &rng).them
        let questions = Array(CompatibilityScaleQuestion.all)
        for (index, question) in questions.enumerated() where index % 4 == 0 || index > questions.count - 8 {
            them.lifestyle[question].own = 6 - (you.lifestyle[question].partner ?? 3)
        }
        return MatchSnapshot(matchedAt: Date(), you: you, them: them, isDemo: true)
    }

    /// A profile with an auto-matching photo, verified or not yet.
    static func photoModel(verified: Bool) -> ProfileCreationViewModel {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: completedState()),
                                             repository: InMemoryProfileRepository())
        let size = CGSize(width: 600, height: 600)
        let image = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor, UIColor.systemIndigo.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                      locations: [0, 0.5, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height),
                                                 options: [])
            UIColor.white.withAlphaComponent(0.85).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 200, y: 120, width: 200, height: 240))
        }
        _ = model.setAutoMatchingPhoto(image)
        if verified, let photo = model.autoMatchingReferencePhoto {
            model.recordAutoMatchingPhotoVerification(
                PhotoVerificationReceipt(photoID: photo.id, imageData: photo.imageData, outcome: .match))
        }
        return model
    }

    static func access() async -> LifetimeAccessStore {
        let access = LifetimeAccessStore(purchasing: AdaptivePurchases(), storage: AdaptiveLedger())
        await access.start()
        return access
    }

    // MARK: - Rendering

    /// The light's layout in this device's safe area, drawn as guides
    /// because Metal content isn't captured by `drawHierarchy`.
    static func stage(_ device: Device) -> WelcomeStageLayout {
        WelcomeStageLayout(size: CGSize(width: device.size.width,
                                        height: device.size.height - device.insets.top - device.insets.bottom))
    }

    private func render<Content: View>(_ content: Content, screen: String, device: Device,
                                       guide: WelcomeStageLayout? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: device.size)
        let host = UIHostingController(rootView: content.preferredColorScheme(.dark))
        host.traitOverrides.horizontalSizeClass = device.size.width < 600 ? .compact : .regular
        host.traitOverrides.verticalSizeClass = device.size.height < 500 ? .compact : .regular
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        let inherited = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: device.insets.top - inherited.top + host.additionalSafeAreaInsets.top,
                                                     left: 0,
                                                     bottom: device.insets.bottom - inherited.bottom + host.additionalSafeAreaInsets.bottom,
                                                     right: 0)
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(900))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: device.size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: device.size))
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: device.size), afterScreenUpdates: true)
            // Safe area guides, so clipped content under the bars is visible.
            UIColor.systemRed.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: device.insets.top - 1, width: device.size.width, height: 1))
            context.fill(CGRect(x: 0, y: device.size.height - device.insets.bottom, width: device.size.width, height: 1))
            if let guide {
                let c = CGPoint(x: guide.lightCenter.x, y: guide.lightCenter.y + device.insets.top), u = guide.unit
                UIColor.cyan.withAlphaComponent(0.6).setStroke()
                UIBezierPath(rect: CGRect(x: c.x - 0.45 * u, y: c.y - 1.02 * u, width: 0.9 * u, height: 2.04 * u)).stroke()
                UIColor.magenta.withAlphaComponent(0.6).setStroke()
                UIBezierPath(ovalIn: CGRect(x: c.x - u, y: c.y - u, width: 2 * u, height: 2 * u)).stroke()
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        let directory = ProcessInfo.processInfo.environment["ADAPTIVE_RENDER_DIR"]
            .map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(screen)--\(device.name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        XCTAssertEqual(image.size, device.size)
    }
}

@MainActor
private final class AdaptiveLedger: EarlyAccessLedgerStoring {
    func load() throws -> EarlyAccessLedger { EarlyAccessLedger() }
    func save(_ ledger: EarlyAccessLedger) throws {}
}

@MainActor
private final class AdaptivePurchases: LifetimePurchasing {
    func products() async throws -> [LifetimeStoreProduct] { [] }
    func snapshot() async -> LifetimeStoreSnapshot {
        .init(entitlements: [.init(productID: .lifetime, originalID: "adaptive", originalPurchaseDate: Date())])
    }
    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(_ transaction: LifetimeStoreTransaction) async {}
}
