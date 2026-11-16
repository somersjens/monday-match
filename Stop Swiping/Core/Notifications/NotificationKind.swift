import Foundation

/// Which switch in the notification settings governs a notification.
enum NotificationCategory: String, Codable, CaseIterable {
    /// Required privacy and account actions. Not muted by the nudges switch,
    /// because the app cannot work without them.
    case account
    /// Real events: matches and messages.
    case transactional
    /// Useful reminders about something waiting for the user.
    case reminder
    /// Playful re-engagement.
    case engagement

    /// Reminders and engagement share the weekly budget and the nudges switch.
    var isNudge: Bool { self == .reminder || self == .engagement }

    /// `UNNotificationCategory` identifiers, registered by the engine.
    var identifier: String { "stopswiping.\(rawValue)" }
}

/// Every notification the app can send. The raw values are stable: they are
/// stored in the ledger and travel in push payloads.
enum NotificationKind: String, Codable, CaseIterable {
    // Matching and conversations
    case matchNew = "match_new"
    case firstMatch = "first_match"
    case messageNew = "message_new"
    case matchEnded = "match_ended"
    case conversationQuiet = "conversation_quiet"
    case messageUnanswered = "message_unanswered"
    case matchNoConversation = "match_no_conversation"
    case messageNotSent = "message_not_sent"
    // Privacy and onboarding
    case privacyRequired = "privacy_required"
    case privacyUpdated = "privacy_updated"
    case firstMatchmaking = "first_matchmaking"
    case onboardingIncomplete = "onboarding_incomplete"
    // Re-engagement and preferences
    case lowerStandards = "lower_standards"
    case compatibilityMonthly = "compatibility_monthly"
    case autoMatchingIdle = "auto_matching_idle"
    case matchingSetupIncomplete = "matching_setup_incomplete"
    case welcomeBack = "welcome_back"

    var category: NotificationCategory {
        switch self {
        case .privacyRequired, .privacyUpdated, .matchingSetupIncomplete: .account
        case .matchNew, .firstMatch, .messageNew, .matchEnded, .messageNotSent: .transactional
        case .conversationQuiet, .messageUnanswered, .matchNoConversation, .firstMatchmaking,
             .onboardingIncomplete, .compatibilityMonthly: .reminder
        case .lowerStandards, .autoMatchingIdle, .welcomeBack: .engagement
        }
    }

    /// 1 is the most important. Decides who gets the weekly budget.
    var priority: Int {
        switch self {
        case .privacyRequired, .privacyUpdated, .matchingSetupIncomplete: 1
        case .matchNew, .firstMatch, .messageNew, .matchEnded, .messageNotSent: 2
        case .messageUnanswered, .matchNoConversation: 3
        case .conversationQuiet, .firstMatchmaking, .onboardingIncomplete, .compatibilityMonthly: 4
        case .lowerStandards, .autoMatchingIdle, .welcomeBack: 5
        }
    }

    /// The shortest time between two deliveries of the same kind, on top of
    /// never repeating a dedupe key.
    var cooldown: TimeInterval {
        let day: TimeInterval = 86_400
        switch self {
        case .matchNew, .firstMatch, .messageNew, .matchEnded: return 0
        case .messageNotSent: return 2 * 3_600
        case .messageUnanswered, .matchNoConversation: return day
        case .conversationQuiet: return 3 * day
        case .privacyRequired, .privacyUpdated: return 3 * day
        case .onboardingIncomplete: return 3 * day
        case .matchingSetupIncomplete, .firstMatchmaking: return 7 * day
        case .compatibilityMonthly, .lowerStandards, .welcomeBack: return 30 * day
        case .autoMatchingIdle: return 14 * day
        }
    }

    /// Sent by the server while the app is closed rather than planned here.
    var isServerSent: Bool { self == .matchNew || self == .firstMatch || self == .messageNew || self == .matchEnded }

    /// Shown in the app only, never as a system notification.
    var isInAppOnly: Bool { self == .welcomeBack }
}
