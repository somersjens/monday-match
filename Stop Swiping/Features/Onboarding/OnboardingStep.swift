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
            return L10n("Relationship type")
        case .profileBasics:
            return L10n("Your profile")
        case .interests:
            return L10n("Your interests")
        case .compatibility:
            return L10n("Compatibility")
        case .photos:
            return L10n("Your photos")
        case .review:
            return L10n("Profile preview")
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
