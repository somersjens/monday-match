import XCTest
@testable import Stop_Swiping

@MainActor
final class ProfileDeletionTests: XCTestCase {
    func testDeletingWithoutAnAccountErasesEveryLocalProfileStore() async throws {
        let suite = "ProfileDeletionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let repository = InMemoryProfileRepository()
        try repository.saveProfile(.mockCompleted)
        let store = InMemoryProfileCreationStore(state: ProfileCreationState(today: .today(), applicationLanguage: "en"))
        defaults.set(Data([1]), forKey: SavedMatchStore.storageKey)
        defaults.set("en", forKey: AppLanguageSettings.storageKey)

        let service = ProfileDeletionService(profileRepository: repository, profileCreationStore: store,
                                             server: nil, authService: MockAuthService(), defaults: defaults)
        try await service.deleteProfile()

        XCTAssertNil(try repository.loadProfile())
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: SavedMatchStore.storageKey))
        // The language belongs to the phone, not the profile.
        XCTAssertEqual(defaults.string(forKey: AppLanguageSettings.storageKey), "en")
    }

    func testTheNotificationStepComesOnlyAfterAnAccountAndBeforeAnyDecision() {
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: false, notificationState: .notDetermined), .account)
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: .notDetermined), .notifications)
        XCTAssertEqual(AutoMatchingEntryStep.resolve(hasAccount: true, notificationState: .denied), .matching)
    }
}
