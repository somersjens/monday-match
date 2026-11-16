import Foundation
import Observation
import XCTest
import UIKit
import CoreImage
@testable import Stop_Swiping

@MainActor
final class AppLocalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppLanguageSettings.shared.language = .english
    }

    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    func testDeviceLanguageIsDefaultAndTheChosenLanguagePersists() throws {
        let suite = "AppLocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["nl-NL", "en-GB"]).language, .dutch)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["nl-BE"]).language, .dutch)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["de-DE", "en-US"]).language, .english)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["fr-FR"]).language, .english)
        let settings = AppLanguageSettings(defaults: defaults, preferredLanguages: ["en-US"])
        settings.language = .dutch
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .dutch)
        settings.language = .english
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .english)
        settings.language = .dutch
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["en-US"]).language, .dutch,
                       "A chosen language wins over the device language.")
        defaults.set("unsupported", forKey: AppLanguageSettings.storageKey)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults, preferredLanguages: ["en-US"]).language, .english)
        XCTAssertEqual(AppLanguage.allCases, [.english, .dutch])
    }

    func testBothCompiledCatalogsContainEveryTranslation() throws {
        func table(_ language: String) throws -> [String: String] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try table("en")
        let dutch = try table("nl")
        XCTAssertGreaterThan(english.count, 550)
        XCTAssertEqual(Set(english.keys), Set(dutch.keys))
        let expression = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        func placeholders(_ value: String) -> Set<String> {
            Set(expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) })
        }
        for (key, value) in dutch {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertTrue(placeholders(value).isSubset(of: placeholders(key)), key)
        }
    }

    func testInterpolationPreservesNamesBracesAndPercentCharacters() {
        let name = "Alex {1} 100%"
        XCTAssertEqual(AppLocalization.string("Remove \(name)", language: .dutch), "Alex {1} 100% verwijderen")
        XCTAssertEqual(AppLocalization.string("\(40) or older", language: .dutch), "40 of ouder")
        XCTAssertEqual(AppLocalization.string("Step \(3) of \(17)", language: .english), "Step 3 of 17")
    }

    func testChangingLanguageUpdatesQuestionsSummariesAndLanguageNames() {
        XCTAssertEqual(Religion.preferNotToShare.title, "I prefer not to share")
        XCTAssertEqual(ReligionAnswers().partnerSummary, "Open to all")
        XCTAssertEqual(RelationshipPreferenceQuestion.sexualArrangement.options.first?.title, "Only with my partner")
        XCTAssertEqual(LanguageCatalog.option(for: "en").name, "English")
        AppLanguageSettings.shared.language = .dutch
        XCTAssertEqual(Religion.preferNotToShare.title, "Ik deel dit liever niet")
        XCTAssertEqual(ReligionAnswers().ownSummary, "Anders/overgeslagen")
        XCTAssertEqual(ReligionAnswers().partnerSummary, "Open voor alles")
        XCTAssertEqual(ProfileCreationStep.dateOfBirth.title, "Wanneer ben je geboren?")
        XCTAssertEqual(RelationshipPreferenceQuestion.sexualArrangement.options.first?.title, "Alleen met mijn partner")
        XCTAssertEqual(CompatibilityScaleQuestion.aloneTime.title, "Tijd voor jezelf")
        XCTAssertEqual(LanguageCatalog.option(for: "en").name, "Engels")
        AppLanguageSettings.shared.language = .english
        XCTAssertEqual(RelationshipPreferenceQuestion.sexualArrangement.options.first?.title, "Only with my partner")
        XCTAssertEqual(LanguageCatalog.option(for: "en").name, "English")
    }

    func testVisibleTextObservesLanguageChanges() async {
        let changed = expectation(description: "A visible localized string observes a language change")
        withObservationTracking {
            XCTAssertEqual(L10n("Your profile"), "Your profile")
        } onChange: {
            changed.fulfill()
        }
        AppLanguageSettings.shared.language = .dutch
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(L10n("Your profile"), "Je profiel")
    }

    func testExpandedCompatibilityCatalogHasOrderedLocalizedQuestionsAndCompactEndpoints() {
        let english = CompatibilityScaleQuestion.all
        XCTAssertEqual(english.count, 50)
        XCTAssertEqual(Set(english.map(\.id)).count, english.count)
        XCTAssertEqual(english.map(\.step), Array(ProfileCreationStep.allCases.suffix(english.count)))
        XCTAssertEqual(english.first?.step, .aloneTime)
        XCTAssertEqual(english.last?.step, .spendingMoney)

        AppLanguageSettings.shared.language = .dutch
        let dutch = CompatibilityScaleQuestion.all
        XCTAssertEqual(dutch.map(\.id), english.map(\.id))
        XCTAssertEqual(CompatibilityScaleQuestion.sections.count, 7)
        for (original, translated) in zip(english, dutch) {
            XCTAssertNotEqual(translated.title, original.title)
            XCTAssertNotEqual(translated.subtitle, original.subtitle)
            XCTAssertFalse(translated.lowLabel.isEmpty)
            XCTAssertFalse(translated.highLabel.isEmpty)
            XCTAssertLessThanOrEqual(translated.lowLabel.count, 21)
            XCTAssertLessThanOrEqual(translated.highLabel.count, 21)
            XCTAssertEqual(translated.step.title, translated.title)
            XCTAssertEqual(translated.step.subtitle, translated.subtitle)
        }
    }

    func testLanguageChangesKeepProfileDataAndMatchingStable() throws {
        var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 12), applicationLanguage: "en")
        state.languages = ["en", "fr"]
        state.religion = ReligionAnswers(own: .spiritual, acceptedPartnerReligions: [.christian, .other])
        let data = try JSONEncoder().encode(state)
        AppLanguageSettings.shared.language = .dutch
        let restored = try JSONDecoder().decode(ProfileCreationState.self, from: data)
        XCTAssertEqual(restored.languages, ["en", "fr"])
        XCTAssertEqual(restored.religion, state.religion)
        XCTAssertTrue(restored.religion.isMutuallyCompatible(with: ReligionAnswers(own: .christian, acceptedPartnerReligions: [.spiritual])))
        XCTAssertEqual(restored.summary(for: .religion, today: state.birthDateBaseline).value, "Spiritueel")
    }

    func testChoosingOwnReligionOpensPartnerAndDeselectingKeepsOwnSideOpen() {
        var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 12), applicationLanguage: "en")
        state.dateOfBirth = .init(year: 1996, month: 4, day: 21)
        state.currentStep = .religion
        let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
        model.selectOwnReligion(.spiritual)
        XCTAssertEqual(model.state.religion.own, .spiritual)
        XCTAssertEqual(model.currentStep, .religion)
        XCTAssertEqual(model.state.religionPhase, .partner)
        model.setReligionPhase(.own)
        model.selectOwnReligion(.spiritual)
        XCTAssertNil(model.state.religion.own)
        XCTAssertEqual(model.state.religionPhase, .own)
        model.selectOwnReligion(.christian)
        XCTAssertEqual(model.state.religionPhase, .partner)
        XCTAssertTrue(model.goBack(), "Cancel during onboarding returns to the own answer.")
        XCTAssertEqual(model.state.religionPhase, .own)
        XCTAssertEqual(model.state.religion.own, .christian)
    }
}
