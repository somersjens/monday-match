import Foundation
import Observation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case dutch = "nl"

    var id: String { rawValue }
    var name: String { self == .english ? "English" : "Nederlands" }
    var flag: String { self == .english ? "🇬🇧" : "🇳🇱" }
    var locale: Locale { Locale(identifier: rawValue) }
}

@Observable
nonisolated final class AppLanguageSettings: @unchecked Sendable {
    static let shared = AppLanguageSettings()
    static let storageKey = "app.interfaceLanguage"

    // Camera/scan errors can be created off the main actor. Keep reads safe
    // there while preserving Observation updates for every visible string.
    @ObservationIgnored private var storedLanguage: AppLanguage
    private let lock = NSLock()
    private let defaults: UserDefaults

    var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return lock.withLock { storedLanguage }
        }
        set {
            withMutation(keyPath: \.language) {
                lock.withLock {
                    storedLanguage = newValue
                }
                defaults.set(newValue.rawValue, forKey: Self.storageKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedLanguage = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

/// Keeps interpolated values separate from the translation key, so names,
/// user content and numbers are preserved while a sentence can be reordered.
nonisolated struct AppLocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

nonisolated enum AppLocalization {
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { language in
        let bundle = Bundle.main.url(forResource: language.rawValue, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .main
        return (language, bundle)
    })
    private static let placeholders = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)

    static func string(_ message: AppLocalizedMessage, language: AppLanguage) -> String {
        let bundle = bundles[language] ?? .main
        let format = bundle.localizedString(forKey: message.key, value: message.key, table: "Localizable")
        // Most UI labels have no arguments. Avoid a mutable string allocation
        // and a regular-expression scan on every render of those labels.
        guard !message.arguments.isEmpty else { return format }
        let result = NSMutableString(string: format)
        for match in placeholders.matches(in: format, range: NSRange(format.startIndex..., in: format)).reversed() {
            if let index = Int((format as NSString).substring(with: match.range(at: 1))), message.arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: message.arguments[index])
            }
        }
        return result as String
    }
}

nonisolated func L10n(_ message: AppLocalizedMessage) -> String {
    AppLocalization.string(message, language: AppLanguageSettings.shared.language)
}
