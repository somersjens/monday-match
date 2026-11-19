import Foundation

enum Religion: String, Codable, CaseIterable, Hashable {
    case none, spiritual, christian, muslim, jewish, hindu, buddhist, other, preferNotToShare

    var title: String {
        switch self {
        case .none: L10n("No religion")
        case .spiritual: L10n("Spiritual")
        case .christian: L10n("Christian")
        case .muslim: L10n("Muslim")
        case .jewish: L10n("Jewish")
        case .hindu: L10n("Hindu")
        case .buddhist: L10n("Buddhist")
        case .other: L10n("Other")
        case .preferNotToShare: L10n("I prefer not to share")
        }
    }

    /// Atheist and Agnostic were merged into No religion; saved drafts and
    /// uploaded profiles may still carry them.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "atheist", "agnostic": self = .none
        default:
            guard let religion = Religion(rawValue: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Unknown religion \(raw)"))
            }
            self = religion
        }
    }
}

enum ReligionQuestionPhase: String, Codable {
    case own, partner

    /// One question for both parts: the You and Partner tabs say which
    /// one is being answered.
    var title: String { L10n("Your worldview, and what you’re open to?") }
}

struct ReligionAnswers: Codable, Equatable {
    /// Keep nil for the overview; matching always treats a skipped answer as Other.
    var own: Religion?
    var acceptedPartnerReligions: Set<Religion> = Set(Religion.allCases)

    var matchingReligion: Religion { own ?? .other }
    var ownSummary: String { own?.title ?? L10n("Other/Skipped") }
    var effectivePartnerReligions: Set<Religion> {
        acceptedPartnerReligions.isEmpty ? Set(Religion.allCases) : acceptedPartnerReligions
    }
    var partnerSummary: String {
        let accepted = effectivePartnerReligions
        return accepted.count == Religion.allCases.count ? L10n("Open to all")
            : Religion.allCases.filter { accepted.contains($0) }.map(\.title).joined(separator: ", ")
    }

    func isMutuallyCompatible(with other: ReligionAnswers) -> Bool {
        effectivePartnerReligions.contains(other.matchingReligion)
            && other.effectivePartnerReligions.contains(matchingReligion)
    }
}
