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
            return "Inappropriate content"
        case .harassment:
            return "Harassment or threats"
        case .fakeProfile:
            return "Fake or misleading profile"
        case .spam:
            return "Spam or scam"
        case .offlineBehavior:
            return "Concerning offline behavior"
        case .other:
            return "Other"
        }
    }
}
