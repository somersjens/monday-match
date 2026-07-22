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
            return "Monogamous"
        case .polyamorous:
            return "Polyamorous"
        case .openRelationship:
            return "Open relationship"
        case .figuringItOut:
            return "Still figuring it out"
        }
    }

    var description: String {
        switch self {
        case .monogamous:
            return "You are looking for one exclusive romantic relationship."
        case .polyamorous:
            return "You are open to multiple consensual romantic relationships."
        case .openRelationship:
            return "You are interested in a relationship with agreed openness."
        case .figuringItOut:
            return "You are still exploring which relationship structure fits you."
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
