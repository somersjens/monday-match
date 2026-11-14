import Foundation

enum PrivacyConsentKind: String, Identifiable {
    case profile
    case matching
    var id: String { rawValue }
    var version: String { "2026-11-14.v1" }
}

/// A receipt records the specific copy and language that was accepted.
struct PrivacyConsentReceipt: Codable, Equatable {
    let version: String
    let acceptedAt: Date
    let languageCode: String

    func isCurrent(for kind: PrivacyConsentKind) -> Bool { version == kind.version }
}

enum ProfileNextAction: Equatable {
    case name, privacy, explanation, matching
}

extension ProfileCreationState {
    var hasAcceptedProfilePrivacy: Bool { profilePrivacyConsent?.isCurrent(for: .profile) == true }
    var hasAcceptedMatchingPrivacy: Bool { autoMatching.privacyConsent?.isCurrent(for: .matching) == true }
    var canShareProfile: Bool {
        completedAt != nil && !displayName.isEmpty && hasAcceptedProfilePrivacy && !isUnderageLocked
    }
    var nextAction: ProfileNextAction {
        if displayName.isEmpty { return .name }
        if !hasAcceptedProfilePrivacy { return .privacy }
        if hasUnderstoodExplanation != true { return .explanation }
        return .matching
    }
    /// Keep the completed questionnaire and matching preferences, but require
    /// a new name, both consents, the explanation and matching setup again.
    mutating func restartNextActions() {
        profilePrivacyConsent = nil
        hasUnderstoodExplanation = nil
        hasCompletedDemo = nil
        hasUsedProfileExchange = nil
        autoMatching.privacyConsent = nil
        autoMatching.isEnabled = false
        autoMatching.hasCompletedSetup = false
    }

    var showsPhoneHint: Bool { hasUsedProfileExchange != true && hasCompletedDemo != true }
}
