import XCTest
@testable import Stop_Swiping

/// The account's profile is backed up to the person's own iCloud: only what
/// changed is sent, and a deleted profile's backup goes too, also later.
@MainActor
final class ProfileICloudBackupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "ProfileICloudBackupTests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testOnlyChangesAreSentAndOnlyChangedPhotos() async throws {
        let cloud = RecordingBackupStore()
        let backup = ProfileICloudBackup(store: cloud, defaults: defaults)
        var state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        state.displayName = "Alex"
        let first = ProfilePhoto(imageData: Data([1]), order: 0)
        let second = ProfilePhoto(imageData: Data([2]), order: 1)
        var draft = ProfileDraft()
        draft.photos = [first, second]

        try await backup.save(state: state, draft: draft, accountID: "a")
        XCTAssertEqual(cloud.calls.count, 1)
        XCTAssertEqual(cloud.calls.last?.sending, [first.id, second.id])

        try await backup.save(state: state, draft: draft, accountID: "a")
        XCTAssertEqual(cloud.calls.count, 1, "Unchanged: iCloud is not asked")

        state.currentStep = .height
        try await backup.save(state: state, draft: draft, accountID: "a")
        XCTAssertEqual(cloud.calls.count, 1, "The questionnaire step left open is no change")

        state.displayName = "Alex B."
        let third = ProfilePhoto(imageData: Data([3]), order: 1)
        draft.photos = [first, third]
        try await backup.save(state: state, draft: draft, accountID: "a")
        XCTAssertEqual(cloud.calls.count, 2)
        XCTAssertEqual(cloud.calls.last?.sending, [third.id], "Only the new photo travels")
        XCTAssertEqual(cloud.calls.last?.removing, [second.id], "The replaced one is removed")
    }

    func testWithoutICloudNothingIsSentAndItTriesAgainLater() async throws {
        let cloud = RecordingBackupStore()
        cloud.available = false
        let backup = ProfileICloudBackup(store: cloud, defaults: defaults)
        let state = ProfileCreationState(today: .today(), applicationLanguage: "en")
        try await backup.save(state: state, draft: ProfileDraft(), accountID: "a")
        XCTAssertTrue(cloud.calls.isEmpty)
        cloud.available = true
        try await backup.save(state: state, draft: ProfileDraft(), accountID: "a")
        XCTAssertEqual(cloud.calls.count, 1)
    }

    func testAForgottenBackupIsRemovedNowOrOnTheNextTry() async throws {
        let cloud = RecordingBackupStore()
        let backup = ProfileICloudBackup(store: cloud, defaults: defaults)
        cloud.failsDeleting = true
        await backup.forget(accountID: "a")
        XCTAssertTrue(cloud.deleted.isEmpty)
        cloud.failsDeleting = false
        await ProfileICloudBackup(store: cloud, defaults: defaults).retryPendingDeletions()
        XCTAssertEqual(cloud.deleted, ["a"])
        await backup.retryPendingDeletions()
        XCTAssertEqual(cloud.deleted, ["a"], "Done once")
    }
}

@MainActor
private final class RecordingBackupStore: ProfileBackupStoring {
    var available = true
    var failsDeleting = false
    var calls: [(sending: Set<UUID>, removing: Set<UUID>)] = []
    var deleted: [String] = []
    func isAvailable() async throws -> Bool { available }
    func load(accountID: String) async throws -> ProfileBackupCopy? { nil }
    func save(_ copy: ProfileBackupCopy, accountID: String, sending: Set<UUID>, removing: Set<UUID>) async throws {
        calls.append((sending, removing))
    }
    func delete(accountID: String) async throws {
        if failsDeleting { throw CancellationError() }
        deleted.append(accountID)
    }
}
