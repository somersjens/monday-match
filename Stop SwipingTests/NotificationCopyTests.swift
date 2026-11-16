import XCTest
@testable import Stop_Swiping

/// The voice's rules, checked on every line of copy in every language.
@MainActor
final class NotificationCopyTests: XCTestCase {
    private func templates(_ language: AppLanguage) -> [(key: String, template: NotificationCopy.Template)] {
        NotificationCopy.catalog(for: language).flatMap { key, templates in templates.map { (key, $0) } }
    }

    private var allTemplates: [(key: String, template: NotificationCopy.Template)] {
        AppLanguage.allCases.flatMap(templates)
    }

    func testEveryKindHasCopyInEveryLanguage() {
        for language in AppLanguage.allCases {
            for kind in NotificationKind.allCases {
                let keys = NotificationCopy.catalog(for: language).keys
                    .filter { $0 == kind.rawValue || $0.hasPrefix(kind.rawValue + ".") }
                XCTAssertFalse(keys.isEmpty, "No \(language.rawValue) copy for \(kind)")
            }
            XCTAssertEqual(Set(NotificationCopy.catalog(for: language).keys), Set(NotificationCopy.english.keys),
                           language.rawValue)
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
        for language in AppLanguage.allCases {
            for (key, minimum) in minimums {
                XCTAssertGreaterThanOrEqual(NotificationCopy.catalog(for: language)[key]?.count ?? 0, minimum,
                                            "\(language.rawValue) \(key)")
            }
        }
    }

    func testVariantIDsAreUniqueAndBelongToTheirSlot() {
        let ids = allTemplates.map(\.template.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for (key, template) in allTemplates { XCTAssertTrue(template.id.hasPrefix(key + "."), template.id) }
        for (_, template) in templates(.dutch) { XCTAssertTrue(template.id.contains(".nl."), template.id) }
    }

    func testCopyStaysShortAndPunchy() {
        for (_, template) in allTemplates {
            XCTAssertLessThanOrEqual(template.title.count, 50, template.id)
            XCTAssertLessThanOrEqual(template.body.count, 110, template.id)
        }
    }

    /// Nothing in this app is liked, swiped or picked: a match only means
    /// both people meet each other's requirements and minimum scores. No
    /// line, in any language, may claim anyone chose, wants or is waiting
    /// for the user.
    func testNobodyIsSaidToLikeChooseOrWantTheUser() throws {
        let english = try NSRegularExpression(pattern: #"""
            \blike[sd]?\b|\bliking\b|swiped? right|\bpicked you|\bchose you|\binto you|\bcrush|admirer|\bfancies|\bwants? (to )?(meet|see|date|you)|\bwaiting for you|\binterested in you|noticed you|checked you out|\bsuper ?like
            """#.trimmingCharacters(in: .whitespacesAndNewlines))
        let dutch = try NSRegularExpression(pattern: #"""
            leuk vind|\blike[sdt]?\b|geliket|liket|naar rechts|uitgekozen|\bgekozen|\bkiest je|wil je (ontmoeten|zien|daten|leren kennen)|wacht op je|op jou wacht|zit op je te wachten|verliefd|\bcrush|valt op je|interesse in je|geïnteresseerd|aanbidder|ziet je wel zitten
            """#.trimmingCharacters(in: .whitespacesAndNewlines))
        for (language, claims) in [(AppLanguage.english, english), (.dutch, dutch)] {
            for (_, template) in templates(language) {
                let text = (template.title + " " + template.body).lowercased()
                let range = NSRange(text.startIndex..., in: text)
                XCTAssertNil(claims.firstMatch(in: text, range: range), "\(template.id): \(text)")
            }
        }
    }

    /// Names reach the lock screen only in message notifications, and the
    /// planner only fills them in with previews on.
    func testNamesAppearOnlyInMessagePreviews() {
        for (key, template) in allTemplates where template.placeholders.contains("match_name") {
            XCTAssertTrue(key.hasPrefix("message_new.preview"), template.id)
        }
    }

    /// Every language needs the same values, so a Dutch line never waits
    /// for a placeholder English doesn't fill.
    func testPlaceholdersMatchAcrossLanguages() {
        for (key, english) in NotificationCopy.english {
            let needed = english.reduce(into: Set<String>()) { $0.formUnion($1.placeholders) }
            for template in NotificationCopy.dutch[key] ?? [] {
                XCTAssertTrue(template.placeholders.isSubset(of: needed), template.id)
            }
        }
    }

    func testNoScoresReasonsOrBlameOnTheLockScreen() {
        let words = ["%", "score of", "blocked", "reported", "deleted", "they ended", "dumped",
                     "geblokkeerd", "gerapporteerd", "verwijderd", "gedumpt", "heeft het uitgemaakt"]
        for (_, template) in allTemplates {
            let text = (template.title + " " + template.body).lowercased()
            for word in words {
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

    // MARK: - Dutch

    /// Written for Dutch readers, not copied: no line may simply be the
    /// English one, apart from bare placeholders like a sender's name.
    func testDutchIsWrittenNotCopied() {
        let english = Set(templates(.english).flatMap { [$0.template.title, $0.template.body] })
        for (_, template) in templates(.dutch) {
            for text in [template.title, template.body] where text != "{match_name}" {
                XCTAssertFalse(english.contains(text), "\(template.id): \(text)")
            }
        }
    }

    /// Informal "je", like the rest of the app, and the app's own Dutch terms.
    func testDutchSpeaksLikeTheApp() throws {
        let formal = try NSRegularExpression(pattern: #"\b(u|uw|bent u|heeft u)\b"#)
        for (_, template) in templates(.dutch) {
            let text = template.title + " " + template.body
            let lower = text.lowercased()
            XCTAssertNil(formal.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)), template.id)
            XCTAssertFalse(text.contains("Auto-matching") || text.contains("My matches"), template.id)
        }
        let matching = NotificationCopy.dutch["privacy_updated.matching"] ?? []
        XCTAssertTrue(matching.allSatisfy { $0.body.contains("Automatisch matchen") })
        XCTAssertTrue((NotificationCopy.dutch["match_ended"] ?? []).contains { $0.body.contains("Mijn matches") })
    }

    func testDutchCopyIsChosenForADutchApp() throws {
        let slot = NotificationCopy.Slot(.matchNew)
        let dutch = try XCTUnwrap(NotificationCopy.variant(for: slot, installID: "a", sendIndex: 0, language: .dutch))
        XCTAssertTrue(dutch.template.id.contains(".nl."))
        let english = try XCTUnwrap(NotificationCopy.variant(for: slot, installID: "a", sendIndex: 0, language: .english))
        XCTAssertFalse(english.template.id.contains(".nl."))
        let counted = try XCTUnwrap(NotificationCopy.variant(for: .init(.messageNew, "preview_batch"), installID: "a",
                                                             sendIndex: 0, values: ["match_name": "Sam", "count": "3"],
                                                             language: .dutch))
        XCTAssertTrue(counted.body.contains("3") && counted.body.contains("Sam"))
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

    /// The push sender has its own copy file; it must say what the app says,
    /// in every language.
    func testServerCopyMatchesTheAppCatalog() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("supabase/functions/push-dispatch/copy.json")
        let server = try JSONDecoder().decode([String: [String: [NotificationCopy.Template]]].self,
                                              from: Data(contentsOf: url))
        XCTAssertEqual(Set(server.keys), Set(AppLanguage.allCases.map(\.rawValue)))
        let serverKinds = NotificationKind.allCases.filter(\.isServerSent).map(\.rawValue)
        for language in AppLanguage.allCases {
            let catalog = NotificationCopy.catalog(for: language)
            let appKeys = catalog.keys.filter { key in serverKinds.contains { key == $0 || key.hasPrefix($0 + ".") } }
            let copy = server[language.rawValue] ?? [:]
            XCTAssertEqual(Set(copy.keys), Set(appKeys), language.rawValue)
            for key in appKeys { XCTAssertEqual(copy[key], catalog[key], "\(language.rawValue) \(key)") }
        }
    }

    func testDestinationsSurviveTheirLinks() {
        let all: [NotificationDestination] = [.match, .chat, .myMatches, .privacy(.profile), .privacy(.matching),
                                              .autoMatching, .share, .profile, .onboarding, .notificationSettings]
        for destination in all { XCTAssertEqual(NotificationDestination(url: destination.url), destination) }
        XCTAssertNil(NotificationDestination(url: URL(string: "stopswiping://code/abc")!))
        XCTAssertNil(NotificationDestination(url: URL(string: "https://example.com/open/chat")!))
    }
}
