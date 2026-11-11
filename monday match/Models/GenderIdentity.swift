import Foundation

enum GenderIdentity: String, CaseIterable, Codable, Identifiable {
    case woman
    case man
    case nonBinary
    case selfDescribed

    var id: String { rawValue }

    /// The choices offered during onboarding. `selfDescribed` remains only so
    /// profiles stored by earlier builds still decode.
    static let onboardingOptions: [GenderIdentity] = [.man, .woman, .nonBinary]

    var title: String {
        switch self {
        case .woman:
            return "Woman"
        case .man:
            return "Man"
        case .nonBinary:
            return "Beyond Binary"
        case .selfDescribed:
            return "Self-described"
        }
    }

    var symbol: String {
        switch self {
        case .woman:
            return "figure.dress.line.vertical.figure"
        case .man:
            return "figure.stand"
        case .nonBinary:
            return "person.2"
        case .selfDescribed:
            return "text.cursor"
        }
    }
}
