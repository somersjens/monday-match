import Foundation

/// Profile details collected after sign-in. Age, gender, partner preferences,
/// languages and location are collected beforehand in profile creation.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case relationshipType
    case profileBasics
    case interests
    case compatibility
    case photos
    case review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .relationshipType:
            return "Relationship type"
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
