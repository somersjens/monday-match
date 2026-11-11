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
    static let all: [LanguageOption] = {
        let isoCodes = Locale.LanguageCode.isoLanguageCodes
            .map(\.identifier)
            .filter { $0.count == 2 }
        let localeCodes = Locale.availableIdentifiers.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }
        let displayLocale = AppLocale.current
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
    }()

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

    private static func option(code: String, name: String) -> LanguageOption {
        let endonym = Locale(identifier: code).localizedString(forLanguageCode: code)
        let distinctEndonym = endonym.flatMap {
            $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame ? nil : $0
        }
        return LanguageOption(code: code, name: name, endonym: distinctEndonym)
    }
}
