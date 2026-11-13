import Foundation

enum ProfileInterest: String, CaseIterable, Codable, Identifiable {
    case cooking
    case travel
    case fitness
    case music
    case reading
    case gaming
    case nature
    case art
    case movies
    case animals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cooking: return L10n("Cooking")
        case .travel: return L10n("Travel")
        case .fitness: return L10n("Fitness")
        case .music: return L10n("Music")
        case .reading: return L10n("Reading")
        case .gaming: return L10n("Gaming")
        case .nature: return L10n("Nature")
        case .art: return L10n("Art")
        case .movies: return L10n("Movies")
        case .animals: return L10n("Animals")
        }
    }

    var symbol: String {
        switch self {
        case .cooking: return "fork.knife"
        case .travel: return "airplane"
        case .fitness: return "figure.run"
        case .music: return "music.note"
        case .reading: return "book"
        case .gaming: return "gamecontroller"
        case .nature: return "leaf"
        case .art: return "paintpalette"
        case .movies: return "film"
        case .animals: return "pawprint"
        }
    }
}
