import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case dateOfBirth
    case gender
    case lookingFor
    case relationshipType
    case location
    case distance
    case profileBasics
    case interests
    case compatibility
    case photos
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dateOfBirth:
            return "Your age"
        case .gender:
            return "Your gender"
        case .lookingFor:
            return "Who are you looking for?"
        case .relationshipType:
            return "Relationship type"
        case .location:
            return "Your location"
        case .distance:
            return "Matching distance"
        case .profileBasics:
            return "Your profile"
        case .interests:
            return "Your interests"
        case .compatibility:
            return "Compatibility"
        case .photos:
            return "Your photos"
        case .review:
            return "Profile preview"
        }
    }

    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }

    var next: OnboardingStep? {
        Self(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        Self(rawValue: rawValue - 1)
    }
}
