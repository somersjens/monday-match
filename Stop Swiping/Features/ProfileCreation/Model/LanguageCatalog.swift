import Foundation

struct LanguageOption: Identifiable, Hashable {
    let code: String
    let name: String
    /// The language's name in itself, when it differs from `name`.
    let endonym: String?

    var id: String { code }
}

enum LanguageCatalog {
    private static let excludedCodes: Set<String> = ["mul", "und", "zxx", "mis", "root"]

    /// Every language the system has locale data for, named in the app's language.
    static var all: [LanguageOption] {
        catalogs[AppLanguageSettings.shared.language] ?? []
    }

    private static let catalogs: [AppLanguage: [LanguageOption]] = Dictionary(
        uniqueKeysWithValues: AppLanguage.allCases.map { ($0, makeOptions(locale: $0.locale)) }
    )

    private static func makeOptions(locale displayLocale: Locale) -> [LanguageOption] {
        let isoCodes = Locale.LanguageCode.isoLanguageCodes
            .map(\.identifier)
            .filter { $0.count == 2 }
        let localeCodes = Locale.availableIdentifiers.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }
        var seenNames: Set<String> = []
        return Set(isoCodes + localeCodes)
            .subtracting(excludedCodes)
            .compactMap { code -> LanguageOption? in
                guard let name = displayLocale.localizedString(forLanguageCode: code),
                      name.lowercased() != code.lowercased() else { return nil }
                return option(code: code, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .filter { seenNames.insert($0.name.lowercased()).inserted }
    }

    static func option(for code: String) -> LanguageOption {
        if let match = all.first(where: { $0.code == code }) { return match }
        let name = AppLocale.current.localizedString(forLanguageCode: code) ?? code
        return option(code: code, name: name)
    }

    /// Device languages first, so likely additions are one tap away.
    static var suggestedCodes: [String] {
        var seen: Set<String> = []
        return Locale.preferredLanguages
            .compactMap { Locale(identifier: $0).language.languageCode?.identifier }
            .filter { seen.insert($0).inserted }
    }

    /// Where a language's likely country is not the one people picture.
    private static let flagRegions: [String: String] = [
        "en": "GB", "ar": "SA", "fa": "IR", "sw": "TZ", "ms": "MY", "hi": "IN", "ur": "PK"
    ]

    /// A flag emoji for the language's most likely country; nil for
    /// languages without one, such as Esperanto or Latin.
    static func flag(for code: String) -> String? {
        let region = flagRegions[code]
            ?? Locale.Language(identifier: Locale.Language(identifier: code).maximalIdentifier).region?.identifier
        guard let region, region.count == 2, region.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let scalars = region.uppercased().unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 0x41) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func option(code: String, name: String) -> LanguageOption {
        let endonym = Locale(identifier: code).localizedString(forLanguageCode: code)
        let distinctEndonym = endonym.flatMap {
            $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ? nil : $0
        }
        return LanguageOption(code: code, name: name, endonym: distinctEndonym)
    }
}
