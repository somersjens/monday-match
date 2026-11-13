import Foundation

enum ReportReason: String, CaseIterable, Identifiable {
    case inappropriateContent
    case harassment
    case fakeProfile
    case spam
    case offlineBehavior
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inappropriateContent:
            return L10n("Inappropriate content")
        case .harassment:
            return L10n("Harassment or threats")
        case .fakeProfile:
            return L10n("Fake or misleading profile")
        case .spam:
            return L10n("Spam or scam")
        case .offlineBehavior:
            return L10n("Concerning offline behavior")
        case .other:
            return L10n("Other")
        }
    }
}
