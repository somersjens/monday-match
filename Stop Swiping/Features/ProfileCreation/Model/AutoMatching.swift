import Foundation

struct PartnerHeightRange: Codable, Equatable {
    var minimum: Int
    var maximum: Int

    /// The whole scale: height doesn't rule anyone out.
    static let any = PartnerHeightRange(minimum: PartnerHeightRules.lowerBound, maximum: PartnerHeightRules.upperBound)

    var isAny: Bool { self == .any }
}

enum PartnerHeightRules {
    static let lowerBound = HeightRules.range.lowerBound
    static let upperBound = HeightRules.range.upperBound

    static var bounds: ClosedRange<Int> { lowerBound...upperBound }

    static func clamped(minimum: Int, maximum: Int) -> PartnerHeightRange {
        let lower = min(max(minimum, lowerBound), upperBound)
        let upper = min(max(maximum, lower), upperBound)
        return PartnerHeightRange(minimum: lower, maximum: upper)
    }
}

/// Shared by both appearance answers, displayed from 10 down to 1.
enum AppearanceRating {
    static let range = 1...10
    static let descendingScores = Array(range.reversed())

    static func description(for score: Int) -> String {
        switch score {
        case 1: L10n("Thank God for personality")
        case 2: L10n("My mom thinks I'm cute")
        case 3: L10n("Looks aren't everything, right?")
        case 4: L10n("Better after a few drinks")
        case 5: L10n("Not bad, not great")
        case 6: L10n("Pretty decent, actually")
        case 7: L10n("A solid catch")
        case 8: L10n("Certified hottie")
        case 9: L10n("Ridiculously good-looking")
        case 10: L10n("Hollywood's finest")
        default: ""
        }
    }
}

/// Opting in to matches proposed automatically. A photo is optional; when
/// supplied, it is stored with the profile draft and verified before joining.
struct AutoMatchingSettings: Codable, Equatable {
    static let minimumScoreRange = 50...90
    static let minimumScoreStep = 5

    var privacyConsent: PrivacyConsentReceipt?
    var isEnabled = false
    /// Kept when switching off, so the saved setup can be resumed directly.
    var hasCompletedSetup = false
    /// The ID of the photo in `ProfileDraft.photos`.
    var photoID: UUID?
    /// 1–10: how attractive the user finds their own appearance.
    var ownAttractiveness: Int?
    /// 1–10: the lowest acceptable appearance score for a partner.
    var partnerMinimumAttractiveness: Int?
    /// The lowest overall match, in percent, that may be proposed.
    var minimumMatchPercent = 70
    /// Whether proposed partners must have verified their photo.
    var requiresVerifiedPartnerPhoto = true

    var isReady: Bool {
        guard let ownAttractiveness, let partnerMinimumAttractiveness else { return false }
        return AppearanceRating.range.contains(ownAttractiveness) && AppearanceRating.range.contains(partnerMinimumAttractiveness)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, photoID, ownAttractiveness, partnerMinimumAttractiveness, minimumMatchPercent
        case appearanceScaleVersion, requiresVerifiedPartnerPhoto, hasCompletedSetup, privacyConsent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requiresVerifiedPartnerPhoto = try values.decodeIfPresent(Bool.self, forKey: .requiresVerifiedPartnerPhoto) ?? true
        photoID = try values.decodeIfPresent(UUID.self, forKey: .photoID)
        minimumMatchPercent = Self.clampedScore(try values.decodeIfPresent(Int.self, forKey: .minimumMatchPercent) ?? 70)
        // The previous 1–5 answers included importance, not a minimum score.
        // Keep the photo and match threshold, and ask for the new scores.
        if try values.decodeIfPresent(Int.self, forKey: .appearanceScaleVersion) == 1 {
            ownAttractiveness = try values.decodeIfPresent(Int.self, forKey: .ownAttractiveness)
                .flatMap { AppearanceRating.range.contains($0) ? $0 : nil }
            partnerMinimumAttractiveness = try values.decodeIfPresent(Int.self, forKey: .partnerMinimumAttractiveness)
                .flatMap { AppearanceRating.range.contains($0) ? $0 : nil }
        }
        privacyConsent = try values.decodeIfPresent(PrivacyConsentReceipt.self, forKey: .privacyConsent)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) == true && isReady
            && privacyConsent?.isCurrent(for: .matching) == true
        hasCompletedSetup = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? isEnabled
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(privacyConsent, forKey: .privacyConsent)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try values.encode(requiresVerifiedPartnerPhoto, forKey: .requiresVerifiedPartnerPhoto)
        try values.encodeIfPresent(photoID, forKey: .photoID)
        try values.encodeIfPresent(ownAttractiveness, forKey: .ownAttractiveness)
        try values.encodeIfPresent(partnerMinimumAttractiveness, forKey: .partnerMinimumAttractiveness)
        try values.encode(minimumMatchPercent, forKey: .minimumMatchPercent)
        try values.encode(1, forKey: .appearanceScaleVersion)
    }

    static func clampedScore(_ percent: Int) -> Int {
        let stepped = Int((Double(percent) / Double(minimumScoreStep)).rounded()) * minimumScoreStep
        return min(max(stepped, minimumScoreRange.lowerBound), minimumScoreRange.upperBound)
    }
}

/// The answers that rule a potential partner out regardless of personality,
/// in the order the questions are asked.
struct MatchDealbreakers: Equatable {
    enum Pronoun {
        case he
        case she
        case they

        var word: String {
            switch self {
            case .he: "he"
            case .she: "she"
            case .they: "they"
            }
        }
    }

    struct Entry: Equatable {
        let step: ProfileCreationStep
        let text: String
    }

    /// Include unrestricted preferences so they can also be tightened here.
    static let editableSteps: [ProfileCreationStep] = [
        .religion, .partnerAgeRange, .partnerHeightRange, .languages, .location,
        .partnerHasChildren, .futureChildren, .alcohol, .smoking, .drugs
    ]

    let pronoun: Pronoun
    let entries: [Entry]
    var lines: [String] { entries.map(\.text) }

    var heading: String {
        L10n("Even if your potential partner matches 100% on personality, you will not be matched if \(pronoun.word):")
    }

    init(state: ProfileCreationState) {
        let genders = state.partnerGenders
        pronoun = genders == [.man] ? .he : (genders == [.woman] ? .she : .they)
        let singular = pronoun != .they
        func verb(_ one: String, _ many: String) -> String { singular ? one : many }

        var entries: [Entry] = []
        for step in ProfileCreationStep.allCases {
            func append(_ text: String) { entries.append(Entry(step: step, text: text)) }
            switch step {
            case .religion:
                let accepted = state.religion.effectivePartnerReligions
                if accepted.count < Religion.allCases.count {
                    let titles = Religion.allCases.filter { accepted.contains($0) }.map(\.title).joined(separator: ", ")
                    append(L10n("\(verb(L10n("Has"), L10n("Have"))) a religion or worldview outside your preferences (\(titles))"))
                }
            case .partnerAgeRange:
                guard let range = state.partnerAgeRange else { continue }
                var parts: [String] = []
                if range.minimum > PartnerAgeRules.lowerBound { parts.append(L10n("\(range.minimum - 1) or younger")) }
                if range.maximum < PartnerAgeRules.upperBound { parts.append(L10n("\(range.maximum + 1) or older")) }
                if !parts.isEmpty { append("\(verb(L10n("Is"), L10n("Are"))) \(parts.joined(separator: L10n(", or ")))") }
            case .partnerHeightRange:
                let range = state.partnerHeightRange
                var parts: [String] = []
                if range.minimum > PartnerHeightRules.lowerBound { parts.append(L10n("\(range.minimum - 1) cm or shorter")) }
                if range.maximum < PartnerHeightRules.upperBound { parts.append(L10n("\(range.maximum + 1) cm or taller")) }
                if !parts.isEmpty { append("\(verb(L10n("Is"), L10n("Are"))) \(parts.joined(separator: L10n(", or ")))") }
            case .languages:
                let names = state.languages.map { LanguageCatalog.option(for: $0).name }
                if names.count == 1, let name = names.first {
                    append(singular ? L10n("Doesn’t speak \(name)") : L10n("Don’t speak \(name)"))
                } else if !names.isEmpty {
                    append(singular ? L10n("Speaks none of \(names.formatted(.list(type: .or).locale(AppLocale.current)))") : L10n("Speak none of \(names.formatted(.list(type: .or).locale(AppLocale.current)))"))
                }
            case .location:
                if state.location != nil {
                    append(L10n("\(verb(L10n("Lives"), L10n("Live"))) more than \(state.searchRadiusKilometers) km away"))
                }
            case .partnerHasChildren:
                if state.lifestyle.openToPartnerWithChildren == false {
                    append(L10n("\(verb(L10n("Has"), L10n("Have"))) kids"))
                }
            case .futureChildren:
                switch state.lifestyle.futureChildren {
                case .yes: append(singular ? L10n("Doesn’t want kids") : L10n("Don’t want kids"))
                case .no: append(singular ? L10n("Wants kids") : L10n("Want kids"))
                case .notSure, nil: break
                }
            case .alcohol, .smoking, .drugs:
                guard let substance = step.substance,
                      let limit = state.lifestyle[substance].partnerMaximumLevel,
                      limit + 1 < substance.levels.count else { continue }
                let level = substance.levels[limit + 1].lowercased()
                let action = switch substance {
                case .alcohol: verb(L10n("Drinks alcohol"), L10n("Drink alcohol"))
                case .smoking: verb(L10n("Smokes or vapes"), L10n("Smoke or vape"))
                case .drugs: verb(L10n("Uses cannabis or other drugs"), L10n("Use cannabis or other drugs"))
                }
                append(L10n("\(action) \(level) or more often"))
            default:
                continue
            }
        }
        self.entries = entries
    }
}
