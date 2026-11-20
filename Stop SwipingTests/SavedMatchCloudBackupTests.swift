import XCTest
@testable import Stop_Swiping

/// Saved matches go to the person's own iCloud, come back on a new phone, and
/// leave it again one by one or all at once with the profile.
@MainActor
final class SavedMatchCloudBackupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""
    private var photos: MatchPhotoStore!
    private var cloud: FakeSavedMatchCloud!

    override func setUp() {
        super.setUp()
        suite = "SavedMatchCloudBackupTests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        photos = MatchPhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        cloud = FakeSavedMatchCloud()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        photos.clear()
        super.tearDown()
    }

    func testANewPhoneGetsTheBackupAndSendsItsOwnMatchesButNoDemos() async {
        let backedUp = Self.match("Noor")
        cloud.matches[backedUp.id] = CloudSavedMatch(snapshot: backedUp, photo: Data("noor".utf8))
        let saved = SavedMatchStore(defaults: defaults)
        let own = Self.match("Mila"), demo = Self.match("Demo", isDemo: true)
        saved.save(own)
        saved.save(demo)
        photos.save(Data("mila".utf8), for: own.id)

        let backup = makeBackup()
        await backup.sync()

        XCTAssertEqual(Set(saved.matches.map(\.id)), [backedUp.id, own.id, demo.id], "My matches shows them at once")
        XCTAssertEqual(photos.photo(for: backedUp.id), Data("noor".utf8))
        XCTAssertEqual(Set(cloud.matches.keys), [backedUp.id, own.id], "Demo matches stay on the phone")
        XCTAssertEqual(cloud.matches[own.id]?.photo, Data("mila".utf8))
        XCTAssertTrue(backup.pending.isEmpty)
    }

    func testNothingChangedAsksICloudNothing() async {
        let backup = makeBackup()
        await backup.sync()
        let calls = cloud.calls
        await backup.sync()
        XCTAssertEqual(cloud.calls, calls)
    }

    func testDeletingOneMatchRemovesOnlyThatOne() async {
        let saved = SavedMatchStore(defaults: defaults)
        let first = Self.match("Mila"), second = Self.match("Noor")
        saved.save(first)
        saved.save(second)
        let backup = makeBackup()
        await backup.sync()
        XCTAssertEqual(Set(cloud.matches.keys), [first.id, second.id])

        saved.delete(first.id)
        await backup.sync()
        XCTAssertEqual(Set(cloud.matches.keys), [second.id])
    }

    func testAMatchDeletedOfflineStaysDeleted() async {
        let saved = SavedMatchStore(defaults: defaults)
        let match = Self.match("Mila")
        saved.save(match)
        let backup = makeBackup()
        await backup.sync()

        cloud.isReachable = false
        saved.delete(match.id)
        await backup.sync()
        XCTAssertEqual(backup.pending, [match.id], "Kept until iCloud can be reached")

        // Another iCloud account on this phone merges first: the deleted
        // match must not come back from the old backup.
        cloud.isReachable = true
        cloud.account = "other"
        cloud.matches[match.id] = CloudSavedMatch(snapshot: match, photo: nil)
        await backup.sync()
        XCTAssertTrue(saved.matches.isEmpty)
        XCTAssertNil(cloud.matches[match.id])
    }

    func testDeletingTheProfileWipesTheBackupBeforeAnythingIsMerged() async {
        let old = Self.match("Mila")
        cloud.matches[old.id] = CloudSavedMatch(snapshot: old, photo: nil)
        cloud.isReachable = false
        let backup = makeBackup()
        backup.wipe()
        await backup.sync()
        XCTAssertEqual(cloud.fetches, 0, "Nothing comes back while the wipe waits")

        cloud.isReachable = true
        await backup.sync()
        XCTAssertTrue(cloud.matches.isEmpty)
        XCTAssertTrue(SavedMatchStore.stored(defaults: defaults).isEmpty)
    }

    func testWithoutICloudNothingIsLost() async {
        cloud.account = nil
        let saved = SavedMatchStore(defaults: defaults)
        let match = Self.match("Mila")
        let backup = makeBackup()
        saved.save(match)
        await backup.sync()
        XCTAssertTrue(cloud.matches.isEmpty)
        XCTAssertEqual(saved.matches.map(\.id), [match.id])

        cloud.account = "me"
        await backup.sync()
        XCTAssertEqual(Set(cloud.matches.keys), [match.id])
    }

    private func makeBackup() -> SavedMatchCloudBackup {
        SavedMatchCloudBackup(store: cloud, defaults: defaults, photos: photos)
    }

    private static func match(_ name: String, isDemo: Bool = false) -> MatchSnapshot {
        var you = ProfileCreationState(today: .today(), applicationLanguage: "en")
        you.displayName = "Alex"
        you.dateOfBirth = CalendarDate(year: 1994, month: 7, day: 12)
        you.completedAt = Date()
        var them = you
        them.displayName = name
        return MatchSnapshot(matchedAt: Date(), you: you, them: them, isDemo: isDemo)
    }
}

@MainActor
private final class FakeSavedMatchCloud: SavedMatchCloudStoring {
    var matches: [UUID: CloudSavedMatch] = [:]
    var account: String? = "me"
    var isReachable = true
    private(set) var calls = 0
    private(set) var fetches = 0

    private func reach() throws {
        calls += 1
        guard isReachable else { throw URLError(.notConnectedToInternet) }
    }

    func accountID() async throws -> String? {
        try reach()
        return account
    }

    func fetchAll() async throws -> [CloudSavedMatch] {
        try reach()
        fetches += 1
        return Array(matches.values)
    }

    func save(_ match: CloudSavedMatch) async throws {
        try reach()
        matches[match.id] = match
    }

    func delete(_ id: UUID) async throws {
        try reach()
        matches[id] = nil
    }

    func deleteAll() async throws {
        try reach()
        matches = [:]
    }
}
