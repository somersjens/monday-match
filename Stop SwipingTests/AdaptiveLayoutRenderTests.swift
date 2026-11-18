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
            try await render(MatchScoreDetailView(report: match.report, perspective: .yours, name: match.name),
                             screen: "score-detail", device: device)
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
