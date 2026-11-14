import Foundation

enum ReportReason: String, CaseIterable, Identifiable {
    case inappropriateContent
    case harassment
    case hateSpeech
    case fakeProfile
    case spam
    case underage
    case offlineBehavior
    case other

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inappropriateContent: "eye.slash"
        case .harassment: "exclamationmark.bubble"
        case .hateSpeech: "megaphone"
        case .fakeProfile: "person.crop.circle.badge.questionmark"
        case .spam: "envelope.badge"
        case .underage: "figure.child"
        case .offlineBehavior: "figure.walk"
        case .other: "ellipsis.circle"
        }
    }

    var title: String {
        switch self {
        case .inappropriateContent:
            return L10n("Inappropriate content")
        case .harassment:
            return L10n("Harassment or threats")
        case .hateSpeech:
            return L10n("Hate speech or discrimination")
        case .underage:
            return L10n("May be under 18")
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
