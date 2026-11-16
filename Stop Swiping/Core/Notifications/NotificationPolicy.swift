import Foundation

/// The tunable numbers behind every notification decision, in one place.
struct NotificationPolicy: Equatable {
    static let day: TimeInterval = 86_400

    /// Reminders and engagement together, per rolling 7 days.
    var nudgesPerWeek = 2
    /// The shortest time between two nudges.
    var minimumNudgeGap: TimeInterval = 36 * 3_600
    /// No nudge sooner than this after the user was last in the app.
    var activityGrace: TimeInterval = day
    /// Nothing is scheduled closer than this to now.
    var minimumLead: TimeInterval = 60
    /// Nudges further out than this are left for a later replan.
    var horizon: TimeInterval = 45 * day

    var unansweredAfter: TimeInterval = 20 * 3_600
    var quietConversationAfter: TimeInterval = 4 * day
    var noConversationAfter: TimeInterval = day
    var unsentMessageAfter: TimeInterval = 15 * 60
    var privacyRequiredFirst: TimeInterval = day
    var privacyUpdatedFirst: TimeInterval = 12 * 3_600
    var privacyRepeatAfter: TimeInterval = 4 * day
    var onboardingFirst: TimeInterval = day
    var onboardingRepeatAfter: TimeInterval = 4 * day
    var firstMatchmakingAfter: TimeInterval = 7 * day
    var compatibilityMonthlyAfter: TimeInterval = 30 * day
    var standardsPeriod: TimeInterval = 30 * day
    var standardsMinimumScore = 85
    var idleAfter: TimeInterval = 14 * day
    var welcomeBackAfter: TimeInterval = 30 * day
    var setupAttentionAfter: TimeInterval = day
    /// Don't remind about onboarding this close to the early-access deadline
    /// reminder: that one already says it.
    var earlyAccessReminderShield: TimeInterval = 2 * day
    /// Spreads deliveries after quiet hours so they don't all land at 09:00.
    var quietHoursSpreadMinutes = 45

    static let standard = NotificationPolicy()
}
