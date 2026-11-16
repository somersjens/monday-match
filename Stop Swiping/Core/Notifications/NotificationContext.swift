import Foundation

/// Everything the planner may look at, captured at one moment. Built from the
/// profile, the live match and the engine's own signals, so the planner
/// itself stays a pure function that tests can feed directly.
struct NotificationContext: Equatable {
    enum Consent: Equatable {
        case missing
        /// A receipt exists, for an older version of the terms.
        case outdated
        case current(acceptedAt: Date)

        var isCurrent: Bool { if case .current = self { true } else { false } }
        var acceptedAt: Date? { if case .current(let date) = self { date } else { nil } }

        init(_ receipt: PrivacyConsentReceipt?, kind: PrivacyConsentKind) {
            guard let receipt else { self = .missing; return }
            self = receipt.isCurrent(for: kind) ? .current(acceptedAt: receipt.acceptedAt) : .outdated
        }
    }

    /// The active match's conversation, as metadata only.
    struct Conversation: Equatable {
        var matchID: UUID
        var matchedAt: Date
        var messagesFromMe = 0
        var messagesFromPartner = 0
        var lastMessageAt: Date?
        var lastMessageFromPartner = false
        /// The oldest partner message sent after the chat was last opened.
        var oldestUnreadAt: Date?
        /// Encrypted messages queued on this phone, not yet on the server.
        var unsentCount = 0
        /// Changes whenever the set of queued messages does.
        var unsentKey = ""
        /// The conversation is still loading; its counts aren't known yet.
        var isLoaded = true
    }

    var permission: NotificationPermissionState = .notDetermined
    var hasAccount = false

    var onboardingStarted = false
    var onboardingCompleted = false
    var onboardingProgress = 0.0
    var isUnderageLocked = false
    var hasDisplayName = false
    var canShareProfile = false

    var profileConsent: Consent = .missing
    var matchingConsent: Consent = .missing
    /// Auto-matching was set up at some point (it may be switched off).
    var matchingConfigured = false
    var autoMatchingEnabled = false
    /// Set up before, but preferences are now missing, so matching is paused.
    var matchingSetupNeedsAttention = false
    var minimumMatchPercent = 70
    var isSuspended = false

    var conversation: Conversation?
    /// The newest match this account has had, active or ended.
    var lastMatchAt: Date?

    // Signals the engine keeps, because nothing else stores them.
    var lastActiveAt: Date = .distantPast
    var autoMatchingEnabledSince: Date?
    var lastCompatibilityCheckAt: Date?
    var hasEverCheckedCompatibility = false
    var privacyIssueNoticedAt: Date?
    var setupIssueNoticedAt: Date?
    /// The early-access deadline reminder, if one is scheduled.
    var earlyAccessReminderAt: Date?

    /// Matching and compatibility nudges only make sense when the user can
    /// actually share a profile and isn't blocked.
    var matchingAvailable: Bool { hasAccount && canShareProfile && !isSuspended && !isUnderageLocked }

    /// All consent that matching depends on is current.
    var consentComplete: Bool {
        profileConsent.isCurrent && (!matchingConfigured || matchingConsent.isCurrent || matchingConsent == .missing)
    }
}

extension NotificationContext {
    /// The profile half of a context; the engine adds the live match and signals.
    init(profile state: ProfileCreationState?, hasAccount: Bool, permission: NotificationPermissionState) {
        self.init()
        self.permission = permission
        self.hasAccount = hasAccount
        guard let state else { return }
        onboardingStarted = state.furthestStep > .dateOfBirth || state.dateOfBirth != nil
        onboardingCompleted = state.completedAt != nil
        onboardingProgress = state.progress
        isUnderageLocked = state.isUnderageLocked
        hasDisplayName = !state.displayName.isEmpty
        canShareProfile = state.canShareProfile
        profileConsent = Consent(state.profilePrivacyConsent, kind: .profile)
        let matching = state.autoMatching
        matchingConsent = Consent(matching.privacyConsent, kind: .matching)
        matchingConfigured = matching.hasCompletedSetup
        autoMatchingEnabled = matching.isEnabled
        matchingSetupNeedsAttention = matching.hasCompletedSetup && !matching.isReady
        minimumMatchPercent = matching.minimumMatchPercent
        hasEverCheckedCompatibility = state.hasUsedProfileExchange == true
    }
}
