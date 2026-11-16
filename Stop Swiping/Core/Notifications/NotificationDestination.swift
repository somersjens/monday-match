import Foundation

/// Where tapping a notification takes the user. Encoded as
/// `stopswiping://open/<screen>?…` so the same link works from a local
/// notification, a push payload or anywhere else.
enum NotificationDestination: Equatable, Hashable {
    /// The active match, or the arrival animation of a new one.
    case match
    /// The conversation of the active match.
    case chat
    case myMatches
    case privacy(PrivacyConsentKind)
    case autoMatching
    /// The share code, to compare profiles in person.
    case share
    case profile
    /// The questionnaire, which reopens at the step where it stopped.
    case onboarding
    case notificationSettings

    static let scheme = "stopswiping"
    static let host = "open"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch self {
        case .match: components.path = "/match"
        case .chat: components.path = "/chat"
        case .myMatches: components.path = "/matches"
        case .privacy(let kind):
            components.path = "/privacy"
            components.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        case .autoMatching: components.path = "/auto-matching"
        case .share: components.path = "/share"
        case .profile: components.path = "/profile"
        case .onboarding: components.path = "/onboarding"
        case .notificationSettings: components.path = "/notification-settings"
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch components.path {
        case "/match": self = .match
        case "/chat": self = .chat
        case "/matches": self = .myMatches
        case "/privacy":
            let kind = components.queryItems?.first { $0.name == "kind" }?.value.flatMap(PrivacyConsentKind.init(rawValue:))
            self = .privacy(kind ?? .profile)
        case "/auto-matching": self = .autoMatching
        case "/share": self = .share
        case "/profile": self = .profile
        case "/onboarding": self = .onboarding
        case "/notification-settings": self = .notificationSettings
        default: return nil
        }
    }
}
