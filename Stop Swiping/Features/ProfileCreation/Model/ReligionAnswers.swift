import Foundation

enum Religion: String, Codable, CaseIterable, Hashable {
    case none, atheist, agnostic, spiritual, christian, muslim, jewish, hindu, buddhist, other

    var title: String {
        switch self {
        case .none: L10n("No religion")
        case .atheist: L10n("Atheist")
        case .agnostic: L10n("Agnostic")
        case .spiritual: L10n("Spiritual")
        case .christian: L10n("Christian")
        case .muslim: L10n("Muslim")
        case .jewish: L10n("Jewish")
        case .hindu: L10n("Hindu")
        case .buddhist: L10n("Buddhist")
        case .other: L10n("Other")
        }
    }

    var explanation: String? {
        switch self {
        case .atheist: L10n("An atheist is someone who does not believe in a god or gods.")
        case .agnostic: L10n("An agnostic is someone who is unsure whether a god or gods exist, or believes this cannot be known for certain.")
        default: nil
        }
    }
}

enum ReligionQuestionPhase: String, Codable {
    case own, partner

    var title: String {
        switch self {
        case .own: L10n("What is your religion or worldview?")
        case .partner: L10n("Which religions or worldviews are you open to in a partner?")
        }
    }

    var subtitle: String {
        switch self {
        case .own: L10n("Choose one, or skip this question. Tap a selected answer to clear it.")
        case .partner: L10n("Choose all that apply. No selection means open to all.")
        }
    }
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
