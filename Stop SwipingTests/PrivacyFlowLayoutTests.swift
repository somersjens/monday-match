import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class PrivacyFlowLayoutTests: XCTestCase {
    func testRenderAppleAndGoogleAccountOptionsInBothLanguages() async throws {
        let originalLanguage = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            AppLanguageSettings.shared.language = language
            for size in [CGSize(width: 320, height: 568), CGSize(width: 393, height: 852)] {
                try await render(
                    NavigationStack {
                        SignInPlaceholderView(authService: MockAuthService(), onAuthenticated: { _ in })
                    }.preferredColorScheme(.dark),
                    name: "account-options-\(language.rawValue)-\(Int(size.width))", size: size)
            }
        }
    }

    func testAutoMatchingCardHasTheSameHeightAsThePrimaryButton() {
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(), repository: nil)
        let card = UIHostingController(rootView: AutoMatchingCard(viewModel: model, onOpenSettings: {}))
        let primary = UIHostingController(rootView: Button(L10n("Adjust profile")) {}.buttonStyle(GlowButtonStyle()))
        let account = UIHostingController(rootView: AccountCreationCard(onCreateAccount: {}))
        for width: CGFloat in [264, 337, 420] {
            let proposal = CGSize(width: width, height: 1_000)
            let cardHeight = card.sizeThatFits(in: proposal).height
            let primaryHeight = primary.sizeThatFits(in: proposal).height
            XCTAssertEqual(cardHeight, primaryHeight, accuracy: 0.5)
            XCTAssertEqual(cardHeight, OnboardingTheme.buttonHeight, accuracy: 0.5)
            XCTAssertEqual(account.sizeThatFits(in: proposal).height, primaryHeight, accuracy: 0.5)
        }
    }

    func testRenderCompletedProfileBeforeAndAfterUnderstanding() async throws {
        let originalLanguage = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = originalLanguage }
        AppLanguageSettings.shared.language = .dutch
        for understood in [false, true] {
            var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
            state.completedAt = Date()
            state.displayName = "Alex"
            state.profilePrivacyConsent = .init(version: PrivacyConsentKind.profile.version,
                                                acceptedAt: Date(), languageCode: "nl")
            state.hasUnderstoodExplanation = understood
            let access = LifetimeAccessStore(purchasing: ProfileHomePurchases(), storage: ProfileHomeLedger())
            await access.start()
            try await render(
                WelcomeView(profileCreationStore: InMemoryProfileCreationStore(state: state),
                            repository: nil, access: access, onSignIn: {}),
                name: "completed-profile-\(understood ? "account" : "explanation")",
                size: CGSize(width: 393, height: 852))
        }
    }

    func testRenderApprovalAndMatchingCardsInBothLanguages() async throws {
        let originalLanguage = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = originalLanguage }
        for language in AppLanguage.allCases {
            AppLanguageSettings.shared.language = language
            for kind in [PrivacyConsentKind.profile, .matching] {
                try await render(PrivacyConsentView(kind: kind, onAccept: {}),
                                 name: "\(kind.rawValue)-\(language.rawValue)", size: CGSize(width: 393, height: 852))
            }
            try await render(PrivacyPolicyView(), name: "full-policy-\(language.rawValue)",
                             size: CGSize(width: 393, height: 852))
            var state = ProfileCreationState(today: .today(), applicationLanguage: language.rawValue)
            state.completedAt = Date()
            state.displayName = "Alex"
            state.profilePrivacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.profile.version, acceptedAt: Date(), languageCode: language.rawValue)
            state.hasUnderstoodExplanation = true
            state.autoMatching.privacyConsent = PrivacyConsentReceipt(version: PrivacyConsentKind.matching.version, acceptedAt: Date(), languageCode: language.rawValue)
            state.autoMatching.isEnabled = true
            let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
            try await render(
                VStack(spacing: 12) {
                    ProfileNameCard(viewModel: model)
                    Button(L10n("Read about your privacy")) {}.buttonStyle(GlowButtonStyle())
                    AutoMatchingCard(viewModel: model, onOpenSettings: {})
                }.padding(28).background(OnboardingTheme.background).preferredColorScheme(.dark),
                name: "cards-\(language.rawValue)", size: CGSize(width: 320, height: 568))
        }
    }

    func testDemoReplayControlsAreVisibleFromTheFirstFrame() async throws {
        let originalLanguage = AppLanguageSettings.shared.language
        defer { AppLanguageSettings.shared.language = originalLanguage }
        AppLanguageSettings.shared.language = .english
        var state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        state.completedAt = Date()
        state.displayName = "Alex"
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.gender = .man
        state.partnerGenders = [.woman]
        var rng = SystemRandomNumberGenerator()
        let match = DemoMatchGenerator.makeMatch(for: state, shouldMatch: true, using: &rng)
        let size = CGSize(width: 393, height: 852)
        for reveal in [MatchReveal.hidden, .controls] {
            try await render(
                MatchResultOverlay(
                    match: match, report: match.report,
                    frame: MatchStageFrame(center: CGPoint(x: size.width / 2, y: (size.height - 160) / 2),
                                           unit: size.width * 0.42),
                    reveal: reveal, isSaved: false,
                    onShowScores: { _ in }, onShowProfile: {}, onRename: { _ in },
                    onSave: {}, onClose: {}, onDelete: {}, onRestartDemo: {}, onUnderstandDemo: {}
                ).background(OnboardingTheme.background).preferredColorScheme(.dark),
                name: "demo-\(reveal.rawValue)", size: size)
        }
    }

    private func render<Content: View>(_ content: Content, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let host = UIHostingController(rootView: content)
        let container = UIViewController()
        window.rootViewController = container
        window.isHidden = false
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.widthAnchor.constraint(equalToConstant: size.width),
            host.view.heightAnchor.constraint(equalToConstant: size.height),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor)
        ])
        host.didMove(toParent: container)
        container.view.layoutIfNeeded()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        container.view.layoutIfNeeded()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
        window.rootViewController = nil
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("privacy-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("PRIVACY_RENDER \(url.path)")
        XCTAssertEqual(image.size, size)
    }
}

@MainActor
private final class ProfileHomeLedger: EarlyAccessLedgerStoring {
    func load() throws -> EarlyAccessLedger { EarlyAccessLedger() }
    func save(_ ledger: EarlyAccessLedger) throws {}
}

@MainActor
private final class ProfileHomePurchases: LifetimePurchasing {
    func products() async throws -> [LifetimeStoreProduct] { [] }
    func snapshot() async -> LifetimeStoreSnapshot {
        .init(entitlements: [.init(productID: .lifetime, originalID: "layout", originalPurchaseDate: Date())])
    }
    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult { .cancelled }
    func restore() async throws {}
    func finish(_ transaction: LifetimeStoreTransaction) async {}
}
