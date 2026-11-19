import XCTest
@testable import Stop_Swiping

/// The server sends no names; the phone adds them. These tests cover the
/// shared logic the Notification Service Extension runs, and what the app
/// leaves for it in the app group.
@MainActor
final class PushPreviewTests: XCTestCase {
    private let matchID = UUID(uuidString: "A7FA0000-0000-4000-8000-000000000001")!

    private var snapshot: PushPreview.Snapshot {
        PushPreview.Snapshot(names: [matchID.uuidString.lowercased(): "Sam"],
                             single: [.init(id: "a", title: "{match_name}", body: "{match_name} sent you a message.")],
                             batch: [.init(id: "b", title: "{match_name}", body: "{match_name} sent {count} messages.")])
    }

    /// The payload push-dispatch builds for a message with previews on.
    private func payload(preview: String = "1", count: String = "1", kind: String = "message_new",
                         match: String? = nil) -> [AnyHashable: Any] {
        ["aps": ["alert": ["title": "New message", "body": "Open the app to read it."], "mutable-content": 1],
         "kind": kind, "match_id": match ?? matchID.uuidString.lowercased(), "count": count,
         "outbox_id": "7", "preview": preview, "dedupe": "message_new.x.7"]
    }

    func testPreviewAddsTheNameOnThePhone() throws {
        let single = try XCTUnwrap(PushPreview.resolve(payload(), snapshot: snapshot))
        XCTAssertEqual(single.title, "Sam")
        XCTAssertEqual(single.body, "Sam sent you a message.")
        let batch = try XCTUnwrap(PushPreview.resolve(payload(count: "3"), snapshot: snapshot))
        XCTAssertEqual(batch.body, "Sam sent 3 messages.")
        // Match IDs are compared case-insensitively.
        XCTAssertNotNil(PushPreview.resolve(payload(match: matchID.uuidString), snapshot: snapshot))
    }

    func testThePlainTextStaysWhenThePhoneDoesNotKnowEnough() {
        XCTAssertNil(PushPreview.resolve(payload(preview: "0"), snapshot: snapshot), "Previews off")
        XCTAssertNil(PushPreview.resolve(payload(kind: "match_new"), snapshot: snapshot), "Only messages are named")
        XCTAssertNil(PushPreview.resolve(payload(match: UUID().uuidString), snapshot: snapshot), "Another match")
        XCTAssertNil(PushPreview.resolve(payload(), snapshot: nil), "Nothing shared")
        var broken = snapshot
        broken.single = [.init(id: "x", title: "{match_name}", body: "{unknown}")]
        XCTAssertNil(PushPreview.resolve(payload(), snapshot: broken), "A placeholder never reaches the lock screen")
    }

    func testSnapshotRoundTripsAndClearsThroughTheAppGroup() throws {
        let suite = "PushPreviewTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        PushPreview.save(snapshot, to: defaults)
        XCTAssertEqual(PushPreview.load(from: defaults), snapshot)
        PushPreview.save(nil, to: defaults)
        XCTAssertNil(defaults.object(forKey: PushPreview.storageKey))
    }

    func testEngineSharesOnlyTheActiveMatchsName() async throws {
        let suite = "PushPreviewTests-engine-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let group = try XCTUnwrap(UserDefaults(suiteName: suite + ".group"))
        defer { defaults.removePersistentDomain(forName: suite); group.removePersistentDomain(forName: suite + ".group") }
        let engine = NotificationEngine(center: nil, loadProfile: { nil }, defaults: defaults,
                                        language: { .dutch }, previewDefaults: group)
        engine.update(hasAccount: true, earlyAccessReminderAt: nil)
        let match = CloudChatMatch(id: matchID, partnerID: UUID(), partnerName: "Alex", ownScore: 80, partnerScore: 82,
                                   matchedAt: Date())
        engine.updateLiveMatch(match, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [match], isSuspended: false)
        let shared = try XCTUnwrap(engine.pushPreviewSnapshot())
        XCTAssertEqual(shared.names, [matchID.uuidString.lowercased(): "Alex"])
        XCTAssertEqual(shared.single.map(\.id),
                       NotificationCopy.templates(for: .init(.messageNew, "preview"), language: .dutch).map(\.id))
        XCTAssertFalse(shared.batch.isEmpty)

        engine.updateLiveMatch(nil, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [match], isSuspended: false)
        XCTAssertNil(engine.pushPreviewSnapshot(), "No active match, no name")
        engine.updateLiveMatch(match, messages: [], lastReadAt: nil, unsentIDs: [], isConversationLoaded: true,
                               history: [match], isSuspended: false)
        engine.update(hasAccount: false, earlyAccessReminderAt: nil)
        XCTAssertNil(engine.pushPreviewSnapshot(), "Signed out, no name")
    }
}

/// The bytes an App Attest key signs must be exactly what the server parses.
final class AppAttestClientDataTests: XCTestCase {
    func testClientDataIsSortedJSONTheServerChecks() throws {
        let photo = UUID(uuidString: "A7FA0000-0000-4000-8000-0000000000AB")!
        let data = try AppAttestPhotoReporter.clientData(challenge: "q83v+A==", photoID: photo)
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"challenge":"q83v+A==","photo_id":"a7fa0000-0000-4000-8000-0000000000ab","purpose":"photo_verification"}"#)
    }
}
