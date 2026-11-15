import XCTest
@testable import Stop_Swiping

@MainActor
final class RandomFillTests: XCTestCase {
    func testRandomFillAnswersEveryQuestionAndOpensTheLastOne() {
        for _ in 0..<25 {
            let store = InMemoryProfileCreationStore()
            let viewModel = ProfileCreationViewModel(store: store, repository: InMemoryProfileRepository())
            viewModel.fillRandomAnswersForTesting()

            XCTAssertEqual(viewModel.currentStep, ProfileCreationStep.allCases.last)
            for step in ProfileCreationStep.allCases {
                XCTAssertTrue(viewModel.isComplete(step), "\(step) is unanswered")
            }
            XCTAssertNil(viewModel.state.completedAt, "Filling must not finish the profile by itself")
            XCTAssertEqual(store.load()?.currentStep, ProfileCreationStep.allCases.last, "The jump is saved")
            XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        }
    }

    func testProgressKeepsTheFurthestQuestionWhenGoingBack() {
        let store = InMemoryProfileCreationStore()
        let viewModel = ProfileCreationViewModel(store: store, repository: InMemoryProfileRepository())
        viewModel.fillRandomAnswersForTesting()
        let furthest = viewModel.state.progress
        XCTAssertGreaterThan(furthest, 0.9)

        for _ in 0..<5 { XCTAssertTrue(viewModel.goBack()) }
        XCTAssertEqual(viewModel.state.progress, furthest)
        XCTAssertEqual(store.load()?.progress, furthest, "The furthest question is saved")

        XCTAssertEqual(viewModel.submitCurrentStep(), .advanced)
        XCTAssertEqual(viewModel.state.progress, furthest)
    }

    func testRandomFillDoesNothingWhileEditing() {
        let viewModel = ProfileCreationViewModel(store: InMemoryProfileCreationStore(),
                                                 repository: InMemoryProfileRepository())
        viewModel.fillRandomAnswersForTesting()
        XCTAssertEqual(viewModel.submitCurrentStep(), .completed)
        let completed = viewModel.state
        viewModel.beginEditing(.height)
        viewModel.fillRandomAnswersForTesting()
        XCTAssertEqual(viewModel.currentStep, .height)
        XCTAssertEqual(viewModel.state.heightCentimeters, completed.heightCentimeters)
    }
}
