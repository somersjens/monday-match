import XCTest
@testable import Stop_Swiping

/// Repeatable hot-path measurements; compare the same simulator and build mode.
@MainActor
final class AppPerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .dutch
    }

    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    func testCompatibilityAnswerAndScreenReadsPerformance() {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.currentStep = .discussingFeelings
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
        let question = state.currentStep.compatibilityQuestion!
        var reads = 0
        measure {
            for index in 0..<100 {
                model.setCompatibilityOwn(index % 5 + 1, for: question)
                // The header, footer and visible answer read these on an update.
                reads += model.currentStep.title.count
                reads += model.currentStep.subtitle?.count ?? 0
                reads += model.currentStep.compatibilityQuestion?.lowLabel.count ?? 0
                reads += model.canContinue ? 1 : 0
                reads += model.shouldAutoAdvanceAfterAnswerSelection ? 1 : 0
                reads += model.currentStep.next?.number ?? 0
            }
        }
        XCTAssertGreaterThan(reads, 0)
    }

    func testProfileOverviewReadsPerformance() {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        for question in CompatibilityScaleQuestion.all {
            state.lifestyle[question] = CompatibilityScaleAnswer(own: 3, partner: 4, importance: 5)
        }
        let today = state.birthDateBaseline
        var reads = 0
        measure {
            for _ in 0..<10 {
                for step in ProfileCreationStep.allCases {
                    reads += step.shortTitle.count
                    reads += state.summary(for: step, today: today).compact.count
                }
            }
        }
        XCTAssertGreaterThan(reads, 0)
    }

    func testStaticLocalizationPerformance() {
        var reads = 0
        measure {
            for _ in 0..<2_000 {
                reads += L10n("What describes you best?").count
                reads += L10n("What suits your ideal partner best?").count
                reads += L10n("How important is a good match on this?").count
            }
        }
        XCTAssertGreaterThan(reads, 0)
    }

    func testRepeatedProfileReadsPerformance() throws {
        let repository = try FileProfileRepository(filename: "performance-\(UUID().uuidString).json")
        defer { try? repository.deleteProfile() }
        var profile = ProfileDraft()
        profile.photos = [ProfilePhoto(imageData: Data(repeating: 0x42, count: 512 * 1_024), order: 0)]
        try repository.saveProfile(profile)
        var bytes = 0
        measure {
            for _ in 0..<20 {
                bytes += (try? repository.loadProfile())?.photos.first?.imageData.count ?? 0
            }
        }
        XCTAssertGreaterThan(bytes, 0)
    }
}
