import XCTest
@testable import Stop_Swiping

/// The rules: eligibility, consent, timing in the user's time zone, quiet
/// hours, dedupe, cooldowns, priorities and the weekly budget.
@MainActor
final class NotificationPlannerTests: XCTestCase {
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private func calendar(_ zone: String = "Europe/Brussels") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// Monday 16 November 2026, 12:00 in Brussels.
    private var now: Date { calendar().date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))! }

    private func planner(_ zone: String = "Europe/Brussels") -> NotificationPlanner {
        NotificationPlanner(calendar: calendar(zone), installID: "test-install")
    }

    /// A finished, consented profile with an account, last active right now.
    private func context() -> NotificationContext {
        var context = NotificationContext()
        context.permission = .authorized
        context.hasAccount = true
        context.onboardingStarted = true
        context.onboardingCompleted = true
        context.onboardingProgress = 1
        context.hasDisplayName = true
        context.canShareProfile = true
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-day))
        context.lastActiveAt = now
        return context
    }

    private func plan(_ context: NotificationContext, ledger: NotificationLedger? = nil,
                      preferences: NotificationPreferences? = nil, zone: String = "Europe/Brussels",
                      at time: Date? = nil) -> [PlannedNotification] {
        planner(zone).plan(context: context, ledger: ledger ?? NotificationLedger(),
                           preferences: preferences ?? .standard, now: time ?? now)
    }

    private func ledger(delivered: [(NotificationKind, String, Date)]) -> NotificationLedger {
        var ledger = NotificationLedger()
        for (kind, key, date) in delivered {
            ledger.markDelivered(identifier: PlannedNotification.identifier(for: key), kind: kind, dedupeKey: key,
                                 variantID: nil, at: date)
        }
        return ledger
    }

    private func isQuiet(_ date: Date, zone: String = "Europe/Brussels") -> Bool {
        let hour = calendar(zone).component(.hour, from: date)
        return hour >= 22 || hour < 9
    }

    // MARK: - Permission and preferences

    func testNothingIsPlannedWithoutPermission() {
        var context = context()
        context.permission = .denied
        XCTAssertEqual(plan(context), [])
        context.permission = .notDetermined
        XCTAssertEqual(plan(context), [])
    }

    func testNudgesSwitchMutesRemindersButNeverRequiredActions() {
        var context = context()
        context.profileConsent = .outdated
        var preferences = NotificationPreferences.standard
        preferences.tipsAndNudges = false
        let kinds = plan(context, preferences: preferences).map(\.kind)
        XCTAssertEqual(kinds, [.privacyUpdated])
    }

    func testTransactionalSwitchMutesUnsentMessageWarnings() {
        var context = context()
        context.conversation = .init(matchID: UUID(), matchedAt: now, messagesFromMe: 1, unsentCount: 1, unsentKey: "1")
        XCTAssertTrue(plan(context).contains { $0.kind == .messageNotSent })
        var preferences = NotificationPreferences.standard
        preferences.matchesAndMessages = false
        XCTAssertFalse(plan(context, preferences: preferences).contains { $0.kind == .messageNotSent })
    }

    // MARK: - Timing

    func testNudgesWaitADayAfterActivityAndSkipQuietHours() throws {
        var context = context()
        // Accepted the terms long ago: the first-matchmaking reminder is overdue.
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        let reminder = try XCTUnwrap(plan(context).first { $0.kind == .firstMatchmaking })
        XCTAssertGreaterThanOrEqual(reminder.fireDate, now.addingTimeInterval(day))
        XCTAssertFalse(isQuiet(reminder.fireDate))
    }

    func testQuietHoursFollowTheUsersTimeZone() throws {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        // Last active at 22:30 UTC, so the nudge's earliest moment is 22:30 UTC tomorrow.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let lateEvening = utc.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 22, minute: 30))!
        context.lastActiveAt = lateEvening
        let time = lateEvening

        // 22:30 in London is quiet: moved to the next morning after 09:00.
        let london = try XCTUnwrap(plan(context, zone: "Europe/London", at: time).first { $0.kind == .firstMatchmaking })
        XCTAssertFalse(isQuiet(london.fireDate, zone: "Europe/London"))
        XCTAssertGreaterThan(london.fireDate, lateEvening.addingTimeInterval(day))

        // The same moment is 17:30 in New York: delivered as is.
        let newYork = try XCTUnwrap(plan(context, zone: "America/New_York", at: time).first { $0.kind == .firstMatchmaking })
        XCTAssertEqual(newYork.fireDate, lateEvening.addingTimeInterval(day))
    }

    func testDisabledQuietHoursDeliverAtTheTrigger() throws {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        let midnight = calendar().date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 23))!
        context.lastActiveAt = midnight
        var preferences = NotificationPreferences.standard
        preferences.quietHoursEnabled = false
        let reminder = try XCTUnwrap(plan(context, preferences: preferences, at: midnight).first { $0.kind == .firstMatchmaking })
        XCTAssertEqual(reminder.fireDate, midnight.addingTimeInterval(day))
    }

    func testTransactionalNotificationsArriveSilentlyInQuietHours() throws {
        var context = context()
        let late = calendar().date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 23))!
        context.conversation = .init(matchID: UUID(), matchedAt: late, messagesFromMe: 1, unsentCount: 1, unsentKey: "x")
        let warning = try XCTUnwrap(plan(context, at: late).first { $0.kind == .messageNotSent })
        // Not postponed to the morning: it is about the user's own message.
        XCTAssertEqual(warning.fireDate, late.addingTimeInterval(15 * 60))
        XCTAssertEqual(warning.interruption, .passive)
        let daytime = try XCTUnwrap(plan(context).first { $0.kind == .messageNotSent })
        XCTAssertEqual(daytime.interruption, .active)
    }

    // MARK: - Dedupe, cooldown, budget

    func testADeliveredNotificationIsNeverPlannedAgain() {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        XCTAssertTrue(plan(context).contains { $0.kind == .firstMatchmaking })
        let sent = ledger(delivered: [(.firstMatchmaking, "first_matchmaking", now.addingTimeInterval(-hour))])
        XCTAssertFalse(plan(context, ledger: sent).contains { $0.kind == .firstMatchmaking })
    }

    func testIdentifiersAreStableSoReplanningUpdatesInPlace() {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        let first = plan(context)
        let second = plan(context)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.identifier)).count, first.count)
    }

    func testNudgesStayWithinTheWeeklyBudgetAndApart() {
        var context = context()
        // Everything at once: first matchmaking, standards and the away nudge.
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-60 * day))
        context.autoMatchingEnabled = true
        context.matchingConfigured = true
        context.matchingConsent = .current(acceptedAt: now.addingTimeInterval(-60 * day))
        context.autoMatchingEnabledSince = now.addingTimeInterval(-45 * day)
        context.minimumMatchPercent = 90
        context.onboardingCompleted = true
        let nudges = plan(context).filter { $0.kind.category.isNudge }.map(\.fireDate).sorted()
        XCTAssertGreaterThanOrEqual(nudges.count, 2)
        for (earlier, later) in zip(nudges, nudges.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.timeIntervalSince(earlier), 36 * hour)
        }
        for date in nudges {
            let sameWeek = nudges.filter { abs($0.timeIntervalSince(date)) < 7 * day }
            XCTAssertLessThanOrEqual(sameWeek.count, 2)
        }
    }

    func testAFullWeekPushesTheNextNudgeOut() throws {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        let sent = ledger(delivered: [
            (.compatibilityMonthly, "compatibility_monthly.1", now.addingTimeInterval(-5 * day)),
            (.autoMatchingIdle, "auto_matching_idle.1", now.addingTimeInterval(-2 * day)),
        ])
        let reminder = try XCTUnwrap(plan(context, ledger: sent).first { $0.kind == .firstMatchmaking })
        XCTAssertGreaterThanOrEqual(reminder.fireDate, now.addingTimeInterval(2 * day))
    }

    func testHigherPriorityWinsTheBudget() throws {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        context.conversation = nil
        context.autoMatchingEnabled = true
        context.autoMatchingEnabledSince = now.addingTimeInterval(-40 * day)
        context.minimumMatchPercent = 90
        let nudges = plan(context).filter { $0.kind.category.isNudge }
        let first = try XCTUnwrap(nudges.min { $0.fireDate < $1.fireDate })
        // Reminders (priority 4) take the first slot before engagement (5).
        XCTAssertEqual(first.kind.priority, 4)
    }

    // MARK: - Consent

    func testMissingConsentAsksForItAndSuppressesEveryMatchingNudge() {
        var context = context()
        context.profileConsent = .missing
        context.canShareProfile = false
        context.autoMatchingEnabled = true
        context.autoMatchingEnabledSince = now.addingTimeInterval(-40 * day)
        context.minimumMatchPercent = 90
        context.lastCompatibilityCheckAt = now.addingTimeInterval(-40 * day)
        let plan = plan(context)
        XCTAssertEqual(plan.map(\.kind), [.privacyRequired])
        XCTAssertEqual(plan.first?.destination, .privacy(.profile))
        XCTAssertTrue(plan.first?.body.contains("privacy") == true)
    }

    func testConsentReminderStopsAfterTheSecond() throws {
        var context = context()
        context.profileConsent = .missing
        context.privacyIssueNoticedAt = now.addingTimeInterval(-10 * day)
        let prefix = "privacy_required.\(PrivacyConsentKind.profile.version)."
        let once = ledger(delivered: [(.privacyRequired, prefix + "1", now.addingTimeInterval(-day))])
        let second = try XCTUnwrap(plan(context, ledger: once).first { $0.kind == .privacyRequired })
        XCTAssertEqual(second.dedupeKey, prefix + "2")
        XCTAssertGreaterThanOrEqual(second.fireDate, now.addingTimeInterval(3 * day))
        let twice = ledger(delivered: [(.privacyRequired, prefix + "1", now.addingTimeInterval(-6 * day)),
                                       (.privacyRequired, prefix + "2", now.addingTimeInterval(-day))])
        XCTAssertFalse(plan(context, ledger: twice).contains { $0.kind == .privacyRequired })
    }

    func testUpdatedTermsUseClearCopyForWhatIsPaused() throws {
        var context = context()
        context.profileConsent = .outdated
        let profile = try XCTUnwrap(plan(context).first)
        XCTAssertEqual(profile.kind, .privacyUpdated)
        XCTAssertTrue(profile.body.contains("Sharing and matching") || profile.body.contains("sharing and matching"))

        context.profileConsent = .current(acceptedAt: now)
        context.matchingConfigured = true
        context.matchingConsent = .outdated
        let matching = try XCTUnwrap(plan(context).first { $0.kind == .privacyUpdated })
        XCTAssertTrue(matching.body.contains("Auto-matching"))
        XCTAssertEqual(matching.destination, .privacy(.matching))
    }

    func testDutchPlansUseDutchCopyWithTheAppsTerms() throws {
        var context = context()
        context.matchingConfigured = true
        context.matchingConsent = .outdated
        var dutchPlanner = planner()
        dutchPlanner.language = .dutch
        let notice = try XCTUnwrap(dutchPlanner.plan(context: context, ledger: NotificationLedger(),
                                                     preferences: .standard, now: now).first { $0.kind == .privacyUpdated })
        XCTAssertTrue(notice.body.contains("Automatisch matchen"))
        XCTAssertTrue(notice.variantID.contains(".nl."))
        // Same rules, same moment: only the words differ.
        let english = try XCTUnwrap(plan(context).first { $0.kind == .privacyUpdated })
        XCTAssertEqual(notice.fireDate, english.fireDate)
        XCTAssertEqual(notice.identifier, english.identifier)
    }

    func testAcceptingConsentReplacesTheReminderWithMatchingNudges() {
        var context = context()
        context.profileConsent = .missing
        context.canShareProfile = false
        XCTAssertEqual(plan(context).map(\.kind), [.privacyRequired])
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-8 * day))
        context.canShareProfile = true
        let kinds = plan(context).map(\.kind)
        XCTAssertFalse(kinds.contains(.privacyRequired))
        XCTAssertTrue(kinds.contains(.firstMatchmaking))
    }

    // MARK: - Conversations

    func testUnreadMessageGetsOneReminderAfterTheInterval() throws {
        var context = context()
        let unreadAt = now.addingTimeInterval(-2 * hour)
        context.conversation = .init(matchID: UUID(), matchedAt: now.addingTimeInterval(-3 * day),
                                     messagesFromMe: 2, messagesFromPartner: 3, lastMessageAt: unreadAt,
                                     lastMessageFromPartner: true, oldestUnreadAt: unreadAt)
        let reminder = try XCTUnwrap(plan(context).first { $0.kind == .messageUnanswered })
        XCTAssertGreaterThanOrEqual(reminder.fireDate, unreadAt.addingTimeInterval(20 * hour))
        XCTAssertEqual(reminder.destination, .chat)
        XCTAssertFalse(plan(context).contains { $0.kind == .conversationQuiet })
    }

    func testOpeningTheChatReplacesTheUnreadReminderWithALaterQuietOne() throws {
        var context = context()
        let last = now.addingTimeInterval(-2 * hour)
        context.conversation = .init(matchID: UUID(), matchedAt: now.addingTimeInterval(-3 * day),
                                     messagesFromMe: 2, messagesFromPartner: 3, lastMessageAt: last,
                                     lastMessageFromPartner: true, oldestUnreadAt: nil)
        let kinds = plan(context).map(\.kind)
        XCTAssertFalse(kinds.contains(.messageUnanswered))
        let quiet = try XCTUnwrap(plan(context).first { $0.kind == .conversationQuiet })
        XCTAssertGreaterThanOrEqual(quiet.fireDate, last.addingTimeInterval(4 * day))
    }

    func testQuietConversationWaitsLongerWhenTheBallIsInTheirCourt() throws {
        var context = context()
        let last = now.addingTimeInterval(-hour)
        context.conversation = .init(matchID: UUID(), matchedAt: now.addingTimeInterval(-3 * day),
                                     messagesFromMe: 2, messagesFromPartner: 2, lastMessageAt: last,
                                     lastMessageFromPartner: false)
        let quiet = try XCTUnwrap(plan(context).first { $0.kind == .conversationQuiet })
        XCTAssertGreaterThanOrEqual(quiet.fireDate, last.addingTimeInterval(8 * day))
    }

    func testOneSidedConversationIsNotQuietItIsUnanswered() {
        var context = context()
        context.conversation = .init(matchID: UUID(), matchedAt: now.addingTimeInterval(-3 * day),
                                     messagesFromMe: 3, messagesFromPartner: 0,
                                     lastMessageAt: now.addingTimeInterval(-10 * day))
        XCTAssertFalse(plan(context).contains { $0.kind == .conversationQuiet })
    }

    func testANewMatchWithoutMessagesGetsAFirstHelloNudge() throws {
        var context = context()
        context.conversation = .init(matchID: UUID(), matchedAt: now)
        let nudge = try XCTUnwrap(plan(context).first { $0.kind == .matchNoConversation })
        XCTAssertGreaterThanOrEqual(nudge.fireDate, now.addingTimeInterval(day))
    }

    func testAnEndedMatchLeavesNoConversationReminders() {
        var context = context()
        context.conversation = nil
        let conversationKinds: Set<NotificationKind> = [.messageUnanswered, .conversationQuiet, .matchNoConversation,
                                                         .messageNotSent]
        XCTAssertTrue(plan(context).allSatisfy { !conversationKinds.contains($0.kind) })
    }

    func testALoadingConversationPlansNothingAboutIt() {
        var context = context()
        context.conversation = .init(matchID: UUID(), matchedAt: now.addingTimeInterval(-3 * day), isLoaded: false)
        XCTAssertFalse(plan(context).contains { $0.kind == .matchNoConversation })
    }

    // MARK: - Matching nudges

    func testAnActiveMatchSuppressesCompatibilityAndMatchingNudges() {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        context.lastCompatibilityCheckAt = now.addingTimeInterval(-40 * day)
        context.autoMatchingEnabled = true
        context.autoMatchingEnabledSince = now.addingTimeInterval(-40 * day)
        context.minimumMatchPercent = 90
        context.conversation = .init(matchID: UUID(), matchedAt: now, messagesFromMe: 1, messagesFromPartner: 1,
                                     lastMessageAt: now)
        let kinds = Set(plan(context).map(\.kind))
        XCTAssertTrue(kinds.isDisjoint(with: [.firstMatchmaking, .compatibilityMonthly, .lowerStandards, .autoMatchingIdle]))
    }

    func testSuspendedUsersGetNoMatchingNudges() {
        var context = context()
        context.profileConsent = .current(acceptedAt: now.addingTimeInterval(-30 * day))
        context.isSuspended = true
        XCTAssertFalse(plan(context).contains { $0.kind == .firstMatchmaking })
    }

    func testMonthlyCompatibilityReminderFollowsTheLastCheck() throws {
        var context = context()
        let last = now.addingTimeInterval(-10 * day)
        context.lastCompatibilityCheckAt = last
        context.hasEverCheckedCompatibility = true
        let reminder = try XCTUnwrap(plan(context).first { $0.kind == .compatibilityMonthly })
        XCTAssertGreaterThanOrEqual(reminder.fireDate, last.addingTimeInterval(30 * day))
        XCTAssertEqual(reminder.destination, .share)
        // A newer check moves it; the old one never fires.
        context.lastCompatibilityCheckAt = now
        let moved = try XCTUnwrap(plan(context).first { $0.kind == .compatibilityMonthly })
        XCTAssertNotEqual(moved.dedupeKey, reminder.dedupeKey)
        XCTAssertFalse(plan(context).contains { $0.kind == .firstMatchmaking })
    }

    func testStandardsNudgeNeedsAHighBarAMonthAndNoMatch() throws {
        var context = context()
        context.autoMatchingEnabled = true
        let since = now.addingTimeInterval(-31 * day)
        context.autoMatchingEnabledSince = since
        context.minimumMatchPercent = 85
        let nudge = try XCTUnwrap(plan(context).first { $0.kind == .lowerStandards })
        XCTAssertEqual(nudge.destination, .autoMatching)

        context.minimumMatchPercent = 80
        XCTAssertFalse(plan(context).contains { $0.kind == .lowerStandards })

        context.minimumMatchPercent = 90
        context.lastMatchAt = since.addingTimeInterval(day)
        XCTAssertFalse(plan(context).contains { $0.kind == .lowerStandards })

        context.lastMatchAt = nil
        context.autoMatchingEnabledSince = now.addingTimeInterval(-10 * day)
        let early = try XCTUnwrap(plan(context).first { $0.kind == .lowerStandards })
        XCTAssertGreaterThanOrEqual(early.fireDate, now.addingTimeInterval(20 * day))
    }

    func testStandardsNudgeAtMostOncePerThirtyDayPeriod() throws {
        var context = context()
        context.autoMatchingEnabled = true
        let since = now.addingTimeInterval(-35 * day)
        context.autoMatchingEnabledSince = since
        context.minimumMatchPercent = 90
        let key = "lower_standards.\(Int(since.timeIntervalSince1970)).1"
        let sent = ledger(delivered: [(.lowerStandards, key, now.addingTimeInterval(-4 * day))])
        let next = try XCTUnwrap(plan(context, ledger: sent).first { $0.kind == .lowerStandards })
        XCTAssertTrue(next.dedupeKey.hasSuffix(".2"))
        XCTAssertGreaterThanOrEqual(next.fireDate, since.addingTimeInterval(60 * day))
    }

    func testAwayNudgeNeverDuplicatesTheStandardsNudge() {
        var context = context()
        context.autoMatchingEnabled = true
        context.autoMatchingEnabledSince = now.addingTimeInterval(-25 * day)
        context.minimumMatchPercent = 90
        // Standards is due in 5 days, the away nudge in 14: too close together.
        let kinds = plan(context).map(\.kind)
        XCTAssertTrue(kinds.contains(.lowerStandards))
        XCTAssertFalse(kinds.contains(.autoMatchingIdle))

        context.minimumMatchPercent = 70
        XCTAssertTrue(plan(context).contains { $0.kind == .autoMatchingIdle })
    }

    // MARK: - Onboarding

    func testIncompleteOnboardingLinksToTheQuestionnaireWithProgress() throws {
        var context = NotificationContext()
        context.permission = .authorized
        context.onboardingStarted = true
        context.onboardingProgress = 0.42
        context.lastActiveAt = now
        let reminder = try XCTUnwrap(plan(context).first)
        XCTAssertEqual(reminder.kind, .onboardingIncomplete)
        XCTAssertEqual(reminder.destination, .onboarding)
        XCTAssertFalse(reminder.body.contains("{percent}"))
        XCTAssertGreaterThanOrEqual(reminder.fireDate, now.addingTimeInterval(day))
    }

    func testOnboardingReminderStepsAsideForTheEarlyAccessDeadline() {
        var context = NotificationContext()
        context.permission = .authorized
        context.onboardingStarted = true
        context.lastActiveAt = now
        context.earlyAccessReminderAt = now.addingTimeInterval(day + 2 * hour)
        XCTAssertFalse(plan(context).contains { $0.kind == .onboardingIncomplete })
    }

    func testAgeLockedProfilesGetNothing() {
        var context = NotificationContext()
        context.permission = .authorized
        context.onboardingStarted = true
        context.isUnderageLocked = true
        context.lastActiveAt = now
        XCTAssertEqual(plan(context), [])
    }
}
