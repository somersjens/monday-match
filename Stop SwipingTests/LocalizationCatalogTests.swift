import Foundation
import XCTest
@testable import Stop_Swiping

/// `L10n` is a custom function, so Xcode never extracts its keys into the
/// string catalog. These tests read the sources and the catalog directly and
/// fail when a visible string has no entry or a language lacks a translation.
@MainActor
final class LocalizationCatalogTests: XCTestCase {
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let appSources = repository.appendingPathComponent("Stop Swiping")
    private static let catalogURL = appSources.appendingPathComponent("Core/Localization/Localizable.xcstrings")

    override func tearDown() {
        AppLanguageSettings.shared.language = .english
        super.tearDown()
    }

    private func catalog() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.catalogURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    func testEveryLocalizedLiteralInTheAppHasACatalogEntry() throws {
        let keys = Set(try catalog().keys)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 50, "The app sources should be readable from the test.")

        var missing: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for key in Self.localizedLiterals(in: source) where !keys.contains(key) {
                missing.append("\(file.lastPathComponent): \(key)")
            }
        }
        XCTAssertEqual(missing, [], "Add these keys to Localizable.xcstrings")
    }

    func testEveryCatalogEntryIsTranslatedIntoEverySupportedLanguage() throws {
        var untranslated: [String] = []
        for (key, entry) in try catalog() {
            let entry = entry as? [String: Any] ?? [:]
            if entry["shouldTranslate"] as? Bool == false { continue }
            // Symbols and format-only keys ("cm", "–", "%lld") stay as they are.
            guard key.rangeOfCharacter(from: .letters) != nil, key != "cm", key != "km",
                  !key.hasPrefix("%") else { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in AppLanguage.allCases {
                let unit = (localizations[language.rawValue] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                if value.isEmpty { untranslated.append("\(language.rawValue): \(key)") }
            }
        }
        XCTAssertEqual(untranslated.sorted(), [])
    }

    func testDutchDealbreakersUseSingularVerbsForMixedGenders() {
        var state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 12), applicationLanguage: "nl")
        state.partnerGenders = [.man, .woman]
        state.lifestyle.openToPartnerWithChildren = false
        state.lifestyle.futureChildren = .yes
        AppLanguageSettings.shared.language = .dutch

        let dealbreakers = MatchDealbreakers(state: state)
        XCTAssertEqual(dealbreakers.pronoun, .they)
        XCTAssertEqual(dealbreakers.heading,
                       "Zelfs bij een persoonlijkheidsmatch van 100% krijg je geen match als je mogelijke partner:")
        XCTAssertTrue(dealbreakers.lines.contains("Heeft kinderen"))
        XCTAssertTrue(dealbreakers.lines.contains("Wil geen kinderen"))
        for plural in ["Hebben", "Willen", "Zijn ", "Wonen", "Drinken", "Roken", "Gebruiken", "Spreken"] {
            XCTAssertFalse(dealbreakers.lines.contains { $0.hasPrefix(plural) }, plural)
        }
    }

    /// Keys of `L10n("…")` calls, with each interpolation turned into `{n}`
    /// exactly as `AppLocalizedMessage` builds them at runtime.
    static func localizedLiterals(in source: String) -> [String] {
        let characters = Array(source)
        let opener = Array("L10n(\"")
        var keys: [String] = []
        var index = 0
        while index + opener.count <= characters.count {
            if Array(characters[index..<index + opener.count]) == opener,
               index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber) {
                let (key, end) = parseLiteral(characters, from: index + opener.count - 1)
                if let key { keys.append(key) }
                index = max(end, index + 1)
            } else {
                index += 1
            }
        }
        return keys
    }

    /// `start` points at the opening quote. Returns nil for multi-line literals.
    private static func parseLiteral(_ characters: [Character], from start: Int) -> (String?, Int) {
        if start + 2 < characters.count, characters[start + 1] == "\"", characters[start + 2] == "\"" {
            return (nil, start + 3)
        }
        var key = ""
        var placeholder = 0
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                let next = characters[index + 1]
                if next == "(" {
                    var depth = 1
                    var cursor = index + 2
                    while cursor < characters.count, depth > 0 {
                        switch characters[cursor] {
                        case "(": depth += 1; cursor += 1
                        case ")": depth -= 1; cursor += 1
                        case "\"": cursor = parseLiteral(characters, from: cursor).1
                        default: cursor += 1
                        }
                    }
                    key += "{\(placeholder)}"
                    placeholder += 1
                    index = cursor
                    continue
                }
                switch next {
                case "n": key.append("\n")
                case "t": key.append("\t")
                default: key.append(next)
                }
                index += 2
                continue
            }
            if character == "\"" { return (key, index + 1) }
            if character == "\n" { return (nil, index) }
            key.append(character)
            index += 1
        }
        return (nil, index)
    }
}
