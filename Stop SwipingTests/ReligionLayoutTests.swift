import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class ReligionLayoutTests: XCTestCase {
    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    func testReligionFlowRendersAtPhoneSizesAndInBothLanguages() async throws {
        let cases: [(String, CGFloat, CGFloat, ReligionQuestionPhase, DynamicTypeSize, AppLanguage)] = [
            ("en-own", 393, 852, .own, .large, .english),
            ("en-partner", 393, 852, .partner, .large, .english),
            ("nl-partner", 393, 852, .partner, .large, .dutch),
            ("compact", 320, 568, .own, .large, .english),
            ("large-text", 393, 852, .partner, .accessibility1, .english)
        ]
        for (name, width, height, phase, textSize, language) in cases {
            AppLanguageSettings.shared.language = language
            let viewModel = makeViewModel(phase: phase)
            let screen = ProfileCreationFlowView(
                viewModel: viewModel, locationService: LocationService(), canExitFromFirstStep: true,
                onExit: {}, onUnderage: {}, onComplete: {}
            )
            .background(OnboardingTheme.background)
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.locale, language.locale)
            .preferredColorScheme(.dark)
            try await render(screen, name: name, size: CGSize(width: width, height: height))
        }
    }

    func testOverviewFlagAndLanguagePickerRenderInBothLanguages() async throws {
        for language in AppLanguage.allCases {
            AppLanguageSettings.shared.language = language
            let model = makeViewModel(phase: .partner)
            let overview = ProfileOverviewView(viewModel: model, locationService: LocationService(), onUnderage: {})
                .environment(\.locale, language.locale)
            try await render(overview, name: "overview-\(language.rawValue)", size: CGSize(width: 393, height: 852))
            try await render(AppLanguagePicker().background(OnboardingTheme.background),
                             name: "picker-\(language.rawValue)", size: CGSize(width: 393, height: 420))
        }
    }

    private func makeViewModel(phase: ReligionQuestionPhase) -> ProfileCreationViewModel {
        var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 12), applicationLanguage: "en")
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.currentStep = .religion
        state.religionPhase = phase
        if phase == .partner { state.religion.own = .atheist }
        return ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
    }

    private func render<Content: View>(_ screen: Content, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let container = UIViewController()
        let host = UIHostingController(rootView: screen)
        window.rootViewController = container
        window.makeKeyAndVisible()
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
        try await Task.sleep(for: .milliseconds(1400))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKeyAndVisible()
        let attachment = XCTAttachment(image: image)
        attachment.name = "Religion-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("religion-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: url)
        print("RELIGION_RENDER \(url.path)")
        XCTAssertEqual(image.size, size)
    }
}
