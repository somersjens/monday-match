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

    func testLiveMatchDownloadsThePhotoOnceAndForgetsItWhenTheMatchEnds() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MatchPhotoTests-\(UUID())"))
        let repository = PhotoRepository()
        repository.current = CloudChatMatch(id: UUID(), partnerID: UUID(), partnerName: "Mila", ownScore: 80, partnerScore: 84,
                                            matchedAt: Date(), partnerPhotoPath: "mila/photo.jpg", partnerPhotoVerified: true)
        let center = LiveMatchCenter(repository: repository, defaults: defaults)
        let you = Self.profile("Emma")

        await center.refresh(ownProfile: you)
        XCTAssertNotNil(center.partnerPhoto)
        await center.refresh(ownProfile: you)
        XCTAssertEqual(repository.downloads, ["mila/photo.jpg"], "An unchanged photo is not downloaded again")

        repository.current = nil
        await center.refresh(ownProfile: you)
        XCTAssertNil(center.partnerPhoto, "The photo goes with the match")
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
}

@MainActor
private final class PhotoRepository: SecureChatRepository {
    let scope = "photo-test-" + UUID().uuidString
    var current: CloudChatMatch?
    var downloads: [String] = []
    func userID() async throws -> UUID { UUID() }
    func currentMatch() async throws -> CloudChatMatch? { current }
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
