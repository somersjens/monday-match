import Foundation

enum RelationshipType: String, CaseIterable, Codable, Identifiable {
    case monogamous
    case polyamorous
    case openRelationship
    case figuringItOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monogamous:
            return L10n("Monogamous")
        case .polyamorous:
            return L10n("Polyamorous")
        case .openRelationship:
            return L10n("Open relationship")
        case .figuringItOut:
            return L10n("Still figuring it out")
        }
    }

    var description: String {
        switch self {
        case .monogamous:
            return L10n("You are looking for one exclusive romantic relationship.")
        case .polyamorous:
            return L10n("You are open to multiple consensual romantic relationships.")
        case .openRelationship:
            return L10n("You are interested in a relationship with agreed openness.")
        case .figuringItOut:
            return L10n("You are still exploring which relationship structure fits you.")
        }
    }

    var symbol: String {
        switch self {
        case .monogamous:
            return "heart"
        case .polyamorous:
            return "heart.circle"
        case .openRelationship:
            return "arrow.triangle.branch"
        case .figuringItOut:
            return "questionmark.circle"
        }
    }
}
