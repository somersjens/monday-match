import XCTest
@testable import Stop_Swiping

/// The voice's rules, checked on every line of copy.
@MainActor
final class NotificationCopyTests: XCTestCase {
    private var allTemplates: [(key: String, template: NotificationCopy.Template)] {
        NotificationCopy.catalog.flatMap { key, templates in templates.map { (key, $0) } }
    }

    func testEveryKindHasCopy() {
        for kind in NotificationKind.allCases {
            let keys = NotificationCopy.catalog.keys.filter { $0 == kind.rawValue || $0.hasPrefix(kind.rawValue + ".") }
            XCTAssertFalse(keys.isEmpty, "No copy for \(kind)")
        }
    }

    /// What arrives often needs the most lines, so it never feels canned.
    func testFrequentNotificationsHaveTheMostVariants() {
        let minimums: [String: Int] = [
            // Every match and every message.
            "match_new": 8, "message_new.preview": 4, "message_new.preview_batch": 4,
            "message_new.private": 3, "message_new.private_batch": 3,
            // Once per match or per conversation lull.
            "first_match": 4, "match_ended": 5, "conversation_quiet": 5, "message_unanswered": 5,
            "match_no_conversation": 5, "compatibility_monthly": 5,
            // Rare nudges.
            "first_matchmaking": 4, "lower_standards": 4, "auto_matching_idle": 4, "onboarding_incomplete": 4,
        ]
        for (key, minimum) in minimums {
            XCTAssertGreaterThanOrEqual(NotificationCopy.catalog[key]?.count ?? 0, minimum, key)
        }
    }

    func testVariantIDsAreUniqueAndBelongToTheirSlot() {
        let ids = allTemplates.map(\.template.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for (key, template) in allTemplates { XCTAssertTrue(template.id.hasPrefix(key + "."), template.id) }
    }

    func testCopyStaysShortAndPunchy() {
        for (_, template) in allTemplates {
            XCTAssertLessThanOrEqual(template.title.count, 50, template.id)
            XCTAssertLessThanOrEqual(template.body.count, 110, template.id)
        }
    }

    /// Nothing in this app is liked, swiped or picked: a match only means
    /// both people meet each other's requirements and minimum scores. No
    /// line may claim anyone chose, wants or is waiting for the user.
    func testNobodyIsSaidToLikeChooseOrWantTheUser() throws {
        let claims = try NSRegularExpression(pattern: #"""
            \blike[sd]?\b|\bliking\b|swiped? right|\bpicked you|\bchose you|\binto you|\bcrush|admirer|\bfancies|\bwants? (to )?(meet|see|date|you)|\bwaiting for you|\binterested in you|noticed you|checked you out|\bsuper ?like
            """#.trimmingCharacters(in: .whitespacesAndNewlines))
        for (_, template) in allTemplates {
            let text = (template.title + " " + template.body).lowercased()
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(claims.firstMatch(in: text, range: range), "\(template.id): \(text)")
        }
    }

    /// Names reach the lock screen only in message notifications, and the
    /// planner only fills them in with previews on.
    func testNamesAppearOnlyInMessagePreviews() {
        for (key, template) in allTemplates where template.placeholders.contains("match_name") {
            XCTAssertTrue(key.hasPrefix("message_new.preview"), template.id)
        }
    }

    func testNoScoresReasonsOrBlameOnTheLockScreen() {
        for (_, template) in allTemplates {
            let text = (template.title + " " + template.body).lowercased()
            for word in ["%", "score of", "blocked", "reported", "deleted", "they ended", "dumped"] {
                XCTAssertFalse(text.contains(word) && !template.placeholders.contains("percent"), "\(template.id): \(word)")
            }
        }
    }

    func testEmojiAreRationed() {
        for (_, template) in allTemplates {
            let emoji = (template.title + template.body).unicodeScalars.filter { $0.properties.isEmojiPresentation }
            XCTAssertTrue(emoji.isEmpty, template.id)
        }
    }

    func testMissingPlaceholderValuesNeverReachTheScreen() {
        let template = NotificationCopy.Template(id: "x.a", title: "{match_name}", body: "{count} new")
        XCTAssertNil(template.rendered(["count": "2"]))
        XCTAssertNil(template.rendered(["match_name": "", "count": "2"]))
        XCTAssertEqual(template.rendered(["match_name": "Sam", "count": "2"])?.title, "Sam")
        // Variants that need a value are skipped when it's missing.
        let slot = NotificationCopy.Slot(.onboardingIncomplete)
        for index in 0..<6 {
            let copy = NotificationCopy.variant(for: slot, installID: "a", sendIndex: index)
            XCTAssertNotNil(copy)
            XCTAssertFalse(copy!.body.contains("{"))
        }
    }

    func testSendsRotateSoTheSameLineNeverRepeatsBackToBack() {
        let slot = NotificationCopy.Slot(.conversationQuiet)
        for install in ["a", "b", "c", "d"] {
            let first = NotificationCopy.variant(for: slot, installID: install, sendIndex: 0)?.template.id
            let second = NotificationCopy.variant(for: slot, installID: install, sendIndex: 1)?.template.id
            XCTAssertNotEqual(first, second)
        }
    }

    func testABBucketsAreStableAndSpread() {
        let slot = NotificationCopy.Slot(.matchNew)
        let again = NotificationCopy.variant(for: slot, installID: "install-1", sendIndex: 0)?.template.id
        XCTAssertEqual(NotificationCopy.variant(for: slot, installID: "install-1", sendIndex: 0)?.template.id, again)
        let firstSeen = Set((0..<60).compactMap {
            NotificationCopy.variant(for: slot, installID: "install-\($0)", sendIndex: 0)?.template.id
        })
        XCTAssertEqual(firstSeen.count, NotificationCopy.catalog["match_new"]?.count)
    }

    /// The push sender has its own copy file; it must say what the app says.
    func testServerCopyMatchesTheAppCatalog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("supabase/functions/push-dispatch/copy.json")
        let server = try JSONDecoder().decode([String: [NotificationCopy.Template]].self, from: Data(contentsOf: url))
        let serverKinds = NotificationKind.allCases.filter(\.isServerSent).map(\.rawValue)
        let appKeys = NotificationCopy.catalog.keys.filter { key in
            serverKinds.contains { key == $0 || key.hasPrefix($0 + ".") }
        }
        XCTAssertEqual(Set(server.keys), Set(appKeys))
        for key in appKeys { XCTAssertEqual(server[key], NotificationCopy.catalog[key], key) }
    }

    func testDestinationsSurviveTheirLinks() {
        let all: [NotificationDestination] = [.match, .chat, .myMatches, .privacy(.profile), .privacy(.matching),
                                              .autoMatching, .share, .profile, .onboarding, .notificationSettings]
        for destination in all { XCTAssertEqual(NotificationDestination(url: destination.url), destination) }
        XCTAssertNil(NotificationDestination(url: URL(string: "stopswiping://code/abc")!))
        XCTAssertNil(NotificationDestination(url: URL(string: "https://example.com/open/chat")!))
    }
}
