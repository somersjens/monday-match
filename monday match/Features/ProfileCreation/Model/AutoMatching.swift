import Foundation

struct PartnerHeightRange: Codable, Equatable {
    var minimum: Int
    var maximum: Int

    /// The whole scale: height doesn't rule anyone out.
    static let any = PartnerHeightRange(minimum: PartnerHeightRules.lowerBound, maximum: PartnerHeightRules.upperBound)

    var isAny: Bool { self == .any }
}

enum PartnerHeightRules {
    static let lowerBound = 140
    static let upperBound = 220

    static var bounds: ClosedRange<Int> { lowerBound...upperBound }

    static func clamped(minimum: Int, maximum: Int) -> PartnerHeightRange {
        let lower = min(max(minimum, lowerBound), upperBound)
        let upper = min(max(maximum, lower), upperBound)
        return PartnerHeightRange(minimum: lower, maximum: upper)
    }
}

/// Opting in to matches proposed automatically. Only enabled once every
/// requirement is met; the photo itself is stored with the profile draft.
struct AutoMatchingSettings: Codable, Equatable {
    static let minimumScoreRange = 50...90
    static let minimumScoreStep = 5

    var isEnabled = false
    /// The ID of the photo in `ProfileDraft.photos`.
    var photoID: UUID?
    /// 1–5: how attractive the user finds their own appearance.
    var ownAttractiveness: Int?
    /// 1–5: how much a partner's appearance matters.
    var partnerAppearanceImportance: Int?
    /// The lowest overall match, in percent, that may be proposed.
    var minimumMatchPercent = 70

    var isReady: Bool { photoID != nil && ownAttractiveness != nil && partnerAppearanceImportance != nil }

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

    let pronoun: Pronoun
    let lines: [String]

    var heading: String {
        "Even if your potential partner matches 100% on personality, you will not be matched if \(pronoun.word):"
    }

    init(state: ProfileCreationState) {
        let genders = state.partnerGenders
        pronoun = genders == [.man] ? .he : (genders == [.woman] ? .she : .they)
        let singular = pronoun != .they
        func verb(_ one: String, _ many: String) -> String { singular ? one : many }

        var lines: [String] = []
        for step in ProfileCreationStep.allCases {
            switch step {
            case .partnerAgeRange:
                guard let range = state.partnerAgeRange else { continue }
                var parts: [String] = []
                if range.minimum > PartnerAgeRules.lowerBound { parts.append("\(range.minimum - 1) or younger") }
                if range.maximum < PartnerAgeRules.upperBound { parts.append("\(range.maximum + 1) or older") }
                if !parts.isEmpty { lines.append("\(verb("Is", "Are")) \(parts.joined(separator: ", or "))") }
            case .partnerHeightRange:
                let range = state.partnerHeightRange
                var parts: [String] = []
                if range.minimum > PartnerHeightRules.lowerBound { parts.append("\(range.minimum - 1) cm or shorter") }
                if range.maximum < PartnerHeightRules.upperBound { parts.append("\(range.maximum + 1) cm or taller") }
                if !parts.isEmpty { lines.append("\(verb("Is", "Are")) \(parts.joined(separator: ", or "))") }
            case .languages:
                let names = state.languages.map { LanguageCatalog.option(for: $0).name }
                if names.count == 1, let name = names.first {
                    lines.append("\(verb("Doesn’t", "Don’t")) speak \(name)")
                } else if !names.isEmpty {
                    lines.append("\(verb("Speaks", "Speak")) none of \(names.formatted(.list(type: .or)))")
                }
            case .location:
                if state.location != nil {
                    lines.append("\(verb("Lives", "Live")) more than \(state.searchRadiusKilometers) km away")
                }
            case .partnerHasChildren:
                if state.lifestyle.openToPartnerWithChildren == false {
                    lines.append("\(verb("Has", "Have")) kids")
                }
            case .futureChildren:
                switch state.lifestyle.futureChildren {
                case .yes: lines.append("\(verb("Doesn’t", "Don’t")) want kids")
                case .no: lines.append("\(verb("Wants", "Want")) kids")
                case .notSure, nil: break
                }
            case .alcohol, .smoking, .drugs:
                guard let substance = step.substance,
                      let limit = state.lifestyle[substance].partnerMaximumLevel,
                      limit + 1 < substance.levels.count else { continue }
                let level = substance.levels[limit + 1].lowercased()
                let action = switch substance {
                case .alcohol: verb("Drinks alcohol", "Drink alcohol")
                case .smoking: verb("Smokes or vapes", "Smoke or vape")
                case .drugs: verb("Uses cannabis or other drugs", "Use cannabis or other drugs")
                }
                lines.append("\(action) \(level) or more often")
            default:
                continue
            }
        }
        self.lines = lines
    }
}
