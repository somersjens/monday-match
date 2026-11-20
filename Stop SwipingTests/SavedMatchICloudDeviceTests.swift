import XCTest
@testable import Stop_Swiping

/// Runs against the real iCloud of the phone it runs on (the Development
/// environment for Debug builds). Only on a physical device, and only when
/// asked: `TEST_RUNNER_ICLOUD_DEVICE_TEST=1 xcodebuild test ... -only-testing:...`.
/// It adds one test match, reads it back as a new phone would, and removes it;
/// nothing else in the backup is touched.
@MainActor
final class SavedMatchICloudDeviceTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a physical iPhone signed in to iCloud")
        #else
        guard ProcessInfo.processInfo.environment["ICLOUD_DEVICE_TEST"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_ICLOUD_DEVICE_TEST=1 to use the phone's iCloud")
        }
        #endif
    }

    func testAMatchSavedOnOnePhoneComesBackOnAnother() async throws {
        let cloud = CloudKitSavedMatchStore()
        let account = try await cloud.accountID()
        XCTAssertNotNil(account, "The phone must be signed in to iCloud")

        let match = Self.testMatch()
        let photo = Data((0..<4096).map { UInt8($0 % 251) })
        let first = try Phone()
        defer { first.tearDown() }
        first.photos.save(photo, for: match.id)
        let firstStore = SavedMatchStore(defaults: first.defaults)
        firstStore.save(match)
        let firstBackup = SavedMatchCloudBackup(store: cloud, defaults: first.defaults, photos: first.photos)
        await firstBackup.sync()
        XCTAssertTrue(firstBackup.pending.isEmpty, "Everything reached iCloud")

        // Read straight from iCloud: the fields arrive decrypted and whole.
        let stored = try await cloud.fetchAll().first { $0.id == match.id }
        XCTAssertEqual(stored?.snapshot, match)
        XCTAssertEqual(stored?.photo, photo)

        // A new phone with the same Apple ID.
        let second = try Phone()
        defer { second.tearDown() }
        let secondStore = SavedMatchStore(defaults: second.defaults)
        let secondBackup = SavedMatchCloudBackup(store: cloud, defaults: second.defaults, photos: second.photos)
        await secondBackup.sync()
        XCTAssertTrue(secondStore.matches.contains(match), "My matches shows it on the new phone")
        XCTAssertEqual(second.photos.photo(for: match.id), photo)

        // Deleting it there removes it from iCloud.
        secondStore.delete(match.id)
        await secondBackup.sync()
        let remaining = try await cloud.fetchAll()
        XCTAssertFalse(remaining.contains { $0.id == match.id })
    }

    private static func testMatch() -> MatchSnapshot {
        var you = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        you.displayName = "iCloud test"
        you.dateOfBirth = CalendarDate(year: 1994, month: 7, day: 12)
        you.completedAt = Date(timeIntervalSince1970: 1_790_000_000)
        var them = you
        them.displayName = "iCloud test match"
        return MatchSnapshot(matchedAt: Date(timeIntervalSince1970: 1_790_000_000), you: you, them: them)
    }
}

/// A phone's local storage: its own defaults and photo folder.
@MainActor
private struct Phone {
    let defaults: UserDefaults
    let suite: String
    let photos: MatchPhotoStore

    init() throws {
        suite = "SavedMatchICloudDeviceTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        photos = MatchPhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: suite))
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        photos.clear()
    }
}
