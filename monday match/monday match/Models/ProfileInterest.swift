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
        case .cooking: return "Cooking"
        case .travel: return "Travel"
        case .fitness: return "Fitness"
        case .music: return "Music"
        case .reading: return "Reading"
        case .gaming: return "Gaming"
        case .nature: return "Nature"
        case .art: return "Art"
        case .movies: return "Movies"
        case .animals: return "Animals"
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
