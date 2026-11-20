import CoreLocation
import UIKit
import XCTest
@testable import Stop_Swiping

/// The other person's photo in an automatic match, and your own in the demo.
@MainActor
final class MatchPhotoTests: XCTestCase {
    func testActiveMatchDecodesThePartnersPhoto() throws {
        let json = """
        {"id":"\(UUID())","partner_id":"\(UUID())","partner_name":"Mila","own_score":80,"partner_score":84,
         "partner_photo":"abc/def.jpg","partner_photo_verified":true}
        """
        let match = try JSONDecoder().decode(CloudChatMatch.self, from: Data(json.utf8))
        XCTAssertEqual(match.partnerPhotoPath, "abc/def.jpg")
        XCTAssertTrue(match.partnerPhotoVerified)
    }

    func testMatchWithoutPhotoFieldsHasNoPhoto() throws {
        let json = """
        {"id":"\(UUID())","partner_id":"\(UUID())","partner_name":"Mila","own_score":80,"partner_score":84,
         "partner_photo":null}
        """
        let match = try JSONDecoder().decode(CloudChatMatch.self, from: Data(json.utf8))
        XCTAssertNil(match.partnerPhotoPath)
        XCTAssertFalse(match.partnerPhotoVerified)
    }

    func testLiveMatchDownloadsThePhotoOnceAndKeepsACopyAfterTheMatchEnds() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let photos = MatchPhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        defer { photos.clear() }
        let repository = PhotoRepository()
        let id = UUID()
        repository.current = CloudChatMatch(id: id, partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                            matchedAt: Date(), partnerPhotoPath: "mila/photo.jpg", partnerPhotoVerified: true)
        let center = LiveMatchCenter(repository: repository, defaults: defaults, photos: photos)
        let you = Self.profile("Emma")

        await center.refresh(ownProfile: you)
        XCTAssertNotNil(center.partnerPhoto)
        await center.refresh(ownProfile: you)
        XCTAssertEqual(repository.downloads, ["mila/photo.jpg"], "An unchanged photo is not downloaded again")

        repository.current = nil
        await center.refresh(ownProfile: you)
        XCTAssertNil(center.partnerPhoto, "The server's photo goes with the match")
        XCTAssertNotNil(center.keptPartnerPhoto(for: id), "The phone keeps the one it was shown, for a report")
        XCTAssertTrue(center.keptPartnerPhotoWasVerified(id))
    }

    /// Deleting an ended automatic match removes it from My matches and this
    /// phone at once, and from the account's list on the server, also when
    /// that only works on a later try.
    func testDeletingAnEndedMatchRemovesItHereAndOnTheServer() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let photos = MatchPhotoStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        defer { photos.clear() }
        let repository = PhotoRepository()
        var ended = CloudChatMatch(id: UUID(), partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                   matchedAt: Date())
        ended.endedAt = Date()
        ended.endReason = .broken
        repository.history = [ended]
        photos.save(Data([1]), for: ended.id)
        let center = LiveMatchCenter(repository: repository, defaults: defaults, photos: photos)
        await center.loadHistory()
        XCTAssertEqual(center.pastMatches.map(\.id), [ended.id])

        repository.failsDeleting = true
        await center.delete(ended.id)
        XCTAssertTrue(center.pastMatches.isEmpty, "Gone from My matches at once")
        XCTAssertNil(photos.photo(for: ended.id), "Its photo leaves the phone")
        XCTAssertTrue(repository.deleted.isEmpty)

        // The server still lists it until the delete gets through.
        await center.loadHistory()
        XCTAssertTrue(center.pastMatches.isEmpty, "A delete not yet confirmed keeps it hidden")
        repository.failsDeleting = false
        await center.loadHistory()
        XCTAssertEqual(repository.deleted, [ended.id])
    }

    func testDemoMatchesAreMarkedAndKeepTheMarkWhenSaved() throws {
        var generator = SystemRandomNumberGenerator()
        let you = Self.profile("Emma")
        let example = DemoMatchGenerator.makeExample(for: you, using: &generator)
        let fake = DemoMatchGenerator.makeMatch(for: you, shouldMatch: true, using: &generator)
        XCTAssertTrue(example.isDemo)
        XCTAssertTrue(fake.isDemo)
        let decoded = try JSONDecoder().decode(MatchSnapshot.self, from: JSONEncoder().encode(example))
        XCTAssertTrue(decoded.isDemo)

        let scanned = MatchSnapshot(matchedAt: Date(), you: you, them: Self.profile("Mila"))
        XCTAssertFalse(scanned.isDemo)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(scanned)) as? [String: Any])
        json.removeValue(forKey: "storedIsDemo")
        let older = try JSONDecoder().decode(MatchSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(older.isDemo, "Matches saved before the mark existed are not demos")
    }

    func testDistanceIsRoundedAndNeverZero() {
        var them = Self.profile("Mila")
        them.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        let same = MatchSnapshot(matchedAt: Date(), you: Self.profile("Emma"), them: them)
        XCTAssertEqual(same.distanceKilometers, 1)
        them.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.22, longitude: 4.40), source: .map)
        let antwerp = MatchSnapshot(matchedAt: Date(), you: Self.profile("Emma"), them: them)
        XCTAssertEqual(antwerp.distanceKilometers, 51)
    }

    func testExchangedPhotoIsKeptWithItsMatchAndPrunedAfter() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MatchPhotoTests-\(UUID())")
        let store = MatchPhotoStore(directory: directory)
        let kept = UUID(), gone = UUID()
        store.save(Data([1]), for: kept)
        store.save(Data([2]), for: gone)
        store.prune(keeping: [kept])
        XCTAssertEqual(store.photo(for: kept), Data([1]))
        XCTAssertNil(store.photo(for: gone))
        store.clear()
        XCTAssertNil(store.photo(for: kept))
    }

    func testManualMatchingPhotoSettingSurvivesSavingAndStaysPrivate() throws {
        var settings = AutoMatchingSettings()
        XCTAssertFalse(settings.sharesPhotoWithManualMatching, "Off until chosen")
        settings.sharesPhotoWithManualMatching = true
        let decoded = try JSONDecoder().decode(AutoMatchingSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertTrue(decoded.sharesPhotoWithManualMatching)
        var state = Self.profile("Emma")
        state.autoMatching = settings
        XCTAssertFalse(state.sharedCopy(today: .today()).autoMatching.sharesPhotoWithManualMatching)
    }

    private static func profile(_ name: String) -> ProfileCreationState {
        var state = ProfileCreationState(today: .today(), applicationLanguage: "nl")
        state.displayName = name
        state.dateOfBirth = CalendarDate(year: 1996, month: 4, day: 21)
        state.partnerAgeRange = PartnerAgeRange(minimum: 24, maximum: 40, isCustomized: true)
        state.gender = .woman
        state.partnerGenders = [.woman]
        state.languages = ["nl", "en"]
        state.location = SelectedLocation(coordinate: CLLocationCoordinate2D(latitude: 51.05, longitude: 3.72), source: .map)
        state.completedAt = Date()
        return state
    }

    func testPushAsksTheServerAtOnceInsteadOfWaitingForTheNextPoll() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let repository = PhotoRepository()
        let center = LiveMatchCenter(repository: repository, defaults: defaults,
                                     pushesArePermitted: { true }, serverPushDelivered: { _ in false })
        let you = Self.profile("Emma")
        let polling = Task { await center.run { you } }
        defer { polling.cancel() }
        try await Self.waitFor(1) { repository.currentMatchCalls }
        // A push: asked at once. Pushes now count as working, so there is
        // no timer at all without a match.
        center.wake()
        try await Self.waitFor(2) { repository.currentMatchCalls }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(repository.currentMatchCalls, 2, "No polling in between")
    }

    func testComingBackToTheAppAsksOnlyWhenSomethingArrived() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let repository = PhotoRepository()
        var delivered = false
        func open() async throws {
            let center = LiveMatchCenter(repository: repository, defaults: defaults,
                                         pushesArePermitted: { true }, serverPushDelivered: { _ in delivered })
            let polling = Task { await center.run { Self.profile("Emma") } }
            try await Task.sleep(for: .milliseconds(100))
            center.wake()   // marks pushes as working
            try await Task.sleep(for: .milliseconds(100))
            polling.cancel()
            _ = await polling.value
        }
        try await open()
        let afterFirst = repository.currentMatchCalls
        XCTAssertEqual(afterFirst, 2, "First launch asks; the push asks again")
        // Back within six hours, nothing new on the lock screen: no request.
        let quiet = LiveMatchCenter(repository: repository, defaults: defaults,
                                    pushesArePermitted: { true }, serverPushDelivered: { _ in delivered })
        let polling = Task { await quiet.run { Self.profile("Emma") } }
        try await Task.sleep(for: .milliseconds(150))
        polling.cancel(); _ = await polling.value
        XCTAssertEqual(repository.currentMatchCalls, afterFirst)
        // A server notification was delivered while the app was closed: ask.
        delivered = true
        let told = LiveMatchCenter(repository: repository, defaults: defaults,
                                   pushesArePermitted: { true }, serverPushDelivered: { _ in delivered })
        let again = Task { await told.run { Self.profile("Emma") } }
        try await Self.waitFor(afterFirst + 1) { repository.currentMatchCalls }
        again.cancel(); _ = await again.value
    }

    func testActiveMatchListensInsteadOfPolling() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let repository = PhotoRepository()
        let partner = UUID()
        repository.current = CloudChatMatch(id: UUID(), partnerID: partner, partnerName: "Mila", ownScore: 80,
                                            partnerScore: 84, matchedAt: Date())
        let center = LiveMatchCenter(repository: repository, defaults: defaults,
                                     pushesArePermitted: { false }, serverPushDelivered: { _ in false })
        let polling = Task { await center.run { Self.profile("Emma") } }
        defer { polling.cancel() }
        try await Self.waitFor(1) { repository.follows }
        XCTAssertTrue(center.chat?.isFollowedLive == true)
        let asked = repository.currentMatchCalls
        let polled = repository.polls

        // The partner wrote: only the conversation is fetched.
        repository.signal?(MatchSignal(kind: .message, by: partner))
        try await Self.waitFor(polled + 1) { repository.polls }
        // This phone's own message needs no news.
        repository.signal?(MatchSignal(kind: .message, by: UUID()))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(repository.polls, polled + 1)
        XCTAssertEqual(repository.currentMatchCalls, asked, "No current_match for a message")

        // The match ended: asked once, and the line is closed.
        repository.current = nil
        repository.signal?(MatchSignal(kind: .ended, by: nil))
        try await Self.waitFor(asked + 1) { repository.currentMatchCalls }
        try await Self.waitFor(1) { repository.stops }
        XCTAssertNil(center.match)
    }

    private static func waitFor(_ value: Int, _ read: () -> Int) async throws {
        for _ in 0..<300 where read() < value { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(read(), value)
    }
}

@MainActor
private final class PhotoRepository: SecureChatRepository {
    var currentMatchCalls = 0
    var polls = 0, follows = 0, stops = 0
    var signal: (@MainActor (MatchSignal) -> Void)?
    private final class Line: MatchFollowing {
        let onStop: () -> Void
        init(onStop: @escaping () -> Void) { self.onStop = onStop }
        func stop() async { onStop() }
    }
    func follow(_ matchID: UUID, onSignal: @escaping @MainActor (MatchSignal) -> Void) async throws -> MatchFollowing? {
        follows += 1
        signal = onSignal
        return Line { [weak self] in self?.stops += 1 }
    }
    func poll(_ matchID: UUID, after: Int64?) async throws -> ChatPoll {
        polls += 1
        return ChatPoll(closed: current?.id != matchID, keys: "k", partnerReadAt: nil, messages: [])
    }
    let scope = "photo-test-" + UUID().uuidString
    var current: CloudChatMatch?
    var history: [CloudChatMatch] = []
    var deleted: [UUID] = []
    var failsDeleting = false
    var downloads: [String] = []
    func matchHistory() async throws -> [CloudChatMatch] { history }
    func deleteMatch(_ matchID: UUID) async throws {
        if failsDeleting { throw CancellationError() }
        deleted.append(matchID)
        history.removeAll { $0.id == matchID }
    }
    let ownID = UUID()
    func userID() async throws -> UUID { ownID }
    func currentMatch() async throws -> CloudChatMatch? { currentMatchCalls += 1; return current }
    func isClosed(_ matchID: UUID) async throws -> Bool { current?.id != matchID }
    func bundles(_ matchID: UUID) async throws -> [CloudChatBundle] { [] }
    func register(_ matchID: UUID, deviceID: UUID, key: Data, replace: Bool) async throws {}
    func messages(_ matchID: UUID, after: Int64?) async throws -> [CloudChatMessage] { [] }
    func send(_ matchID: UUID, pending: ChatPendingMessage) async throws {}
    func breakMatch(_ matchID: UUID) async throws {}
    func report(_ matchID: UUID, reason: String, details: String) async throws {}
    func partnerPhoto(path: String) async throws -> Data {
        downloads.append(path)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
    }
}
