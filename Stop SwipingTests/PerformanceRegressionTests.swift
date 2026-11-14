import Combine
import ImageIO
import Observation
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class PerformanceRegressionTests: XCTestCase {
    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    func testCompatibilitySelectionPublishesOnceAndRepeatedSelectionDoesNoWork() {
        let state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
        let question = CompatibilityScaleQuestion.aloneTime
        var updates = 0
        let subscription = model.objectWillChange.sink { updates += 1 }
        defer { subscription.cancel() }

        model.setCompatibilityOwn(4, for: question)
        XCTAssertEqual(updates, 1, "Own and prefilled partner values must publish together.")
        XCTAssertEqual(model.state.lifestyle[question].partner, 4)
        model.setCompatibilityOwn(4, for: question)
        XCTAssertEqual(updates, 1)
        model.setCompatibilityPartner(4, for: question)
        XCTAssertEqual(updates, 2, "Explicitly choosing the prefilled value still customizes it.")
        XCTAssertTrue(model.state.lifestyle[question].isPartnerCustomized)
        model.setCompatibilityPartner(4, for: question)
        model.setCompatibilityImportance(3, for: question)
        XCTAssertEqual(updates, 2)
        model.setCompatibilityImportance(5, for: question)
        XCTAssertEqual(updates, 3)
    }

    func testCachedQuestionLookupStillObservesLanguageChanges() {
        AppLanguageSettings.shared.language = .english
        let english = CompatibilityScaleQuestion.sections
        AppLanguageSettings.shared.language = .dutch
        _ = CompatibilityScaleQuestion.sections // Warm both caches.
        AppLanguageSettings.shared.language = .english
        let invalidated = expectation(description: "Cached text observes a language change")
        withObservationTracking {
            XCTAssertEqual(ProfileCreationStep.sharedHobbies.title, "Shared hobbies")
            XCTAssertEqual(CompatibilityScaleQuestion.sections.first?.title, english.first?.title)
        } onChange: {
            invalidated.fulfill()
        }
        AppLanguageSettings.shared.language = .dutch
        wait(for: [invalidated], timeout: 0.1)
        XCTAssertEqual(ProfileCreationStep.sharedHobbies.title, "Gedeelde hobby’s")
        AppLanguageSettings.shared.language = .english
        XCTAssertEqual(ProfileCreationStep.sharedHobbies.title, "Shared hobbies")
    }

    func testFileRepositoryCacheTracksSavesAndDeletionWithoutSharingMutableDrafts() throws {
        let filename = "cache-test-\(UUID().uuidString).json"
        let repository = try FileProfileRepository(filename: filename)
        defer { try? repository.deleteProfile() }
        XCTAssertNil(try repository.loadProfile())
        var original = ProfileDraft()
        original.displayName = "Original"
        try repository.saveProfile(original)
        var copy = try XCTUnwrap(repository.loadProfile())
        copy.displayName = "Unsaved"
        XCTAssertEqual(try repository.loadProfile()?.displayName, "Original")
        try repository.saveProfile(copy)
        XCTAssertEqual(try repository.loadProfile()?.displayName, "Unsaved")
        let reopened = try FileProfileRepository(filename: filename)
        XCTAssertEqual(try reopened.loadProfile()?.displayName, "Unsaved", "The cache and file agree.")
        try repository.deleteProfile()
        XCTAssertNil(try repository.loadProfile())
        XCTAssertNil(try FileProfileRepository(filename: filename).loadProfile())
    }

    func testFailedFileSaveKeepsTheLastSuccessfullySavedProfile() throws {
        let directoryName = "cache-failure-test-\(UUID().uuidString)"
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try FileProfileRepository(filename: "\(directoryName)/profile.json")
        var profile = ProfileDraft()
        profile.displayName = "Saved"
        try repository.saveProfile(profile)
        try FileManager.default.removeItem(at: directory)
        profile.displayName = "Not saved"
        XCTAssertThrowsError(try repository.saveProfile(profile))
        XCTAssertEqual(try repository.loadProfile()?.displayName, "Saved")
    }

    func testPhotoDimensionsArePixelsAndSmallImagesAreNotUpscaled() throws {
        for size in [CGSize(width: 2400, height: 1800), CGSize(width: 1800, height: 2400), CGSize(width: 320, height: 200)] {
            let source = try makeImageData(size: size)
            let data = try ImageProcessingService(maximumDimension: 800).process(source)
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            XCTAssertLessThanOrEqual(max(image.width, image.height), 800)
            XCTAssertLessThanOrEqual(image.width, Int(size.width))
            XCTAssertLessThanOrEqual(image.height, Int(size.height))
            XCTAssertEqual(Double(image.width) / Double(image.height), size.width / size.height, accuracy: 0.01)
        }
    }

    func testPhotoDownsamplingAppliesCameraOrientation() throws {
        let source = try makeImageData(size: CGSize(width: 1200, height: 600))
        let image = try XCTUnwrap(UIImage(data: source)?.cgImage)
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let output = try ImageProcessingService(maximumDimension: 800).process(encoded as Data)
        let decoded = try XCTUnwrap(UIImage(data: output))
        XCTAssertEqual(decoded.cgImage?.width, 400)
        XCTAssertEqual(decoded.cgImage?.height, 800)
        XCTAssertEqual(decoded.imageOrientation, .up)
    }

    func testBackgroundPhotoProcessingMatchesTheSynchronousResultAndRejectsInvalidData() async throws {
        let processor = ImageProcessingService(maximumDimension: 800)
        let input = try makeImageData(size: CGSize(width: 1200, height: 600))
        let background = try await processor.processInBackground(input)
        XCTAssertEqual(background, try processor.process(input))
        do {
            _ = try await processor.processInBackground(Data("invalid".utf8))
            XCTFail("Invalid image data must not become a profile photo.")
        } catch {
            XCTAssertTrue(error is ImageProcessingError)
        }
    }

    func testPhotoPickersStoreBoundedImagesAndPreserveTheirCapacity() async throws {
        let data = try makeImageData(size: CGSize(width: 2000, height: 1000))
        let onboarding = OnboardingViewModel()
        await onboarding.addPhotoData([data, data, data, data])
        XCTAssertEqual(onboarding.draft.photos.count, onboarding.maximumPhotos)
        for photo in onboarding.draft.photos {
            let image = try XCTUnwrap(UIImage(data: photo.imageData)?.cgImage)
            XCTAssertEqual(image.width, 1600)
            XCTAssertEqual(image.height, 800)
        }

        let repository = InMemoryProfileRepository()
        let state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: repository)
        let firstError = await model.setAutoMatchingPhotoInBackground(data)
        XCTAssertNil(firstError)
        let firstID = try XCTUnwrap(model.state.autoMatching.photoID)
        let secondError = await model.setAutoMatchingPhotoInBackground(data)
        XCTAssertNil(secondError)
        XCTAssertNotEqual(model.state.autoMatching.photoID, firstID)
        XCTAssertEqual(try repository.loadProfile()?.photos.count, 1)
        XCTAssertNil(model.autoMatchingPhotoVerification)
        XCTAssertFalse(model.state.autoMatching.isEnabled)
    }

    private func makeImageData(size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}
