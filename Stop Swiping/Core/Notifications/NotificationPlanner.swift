import Foundation

/// One notification the phone should have pending.
struct PlannedNotification: Equatable {
    enum Interruption: String, Equatable {
        /// Arrives silently, without lighting the screen (quiet hours).
        case passive
        case active
    }

    /// Stable for the same dedupe key, so replanning updates in place.
    let identifier: String
    let kind: NotificationKind
    let dedupeKey: String
    let fireDate: Date
    let title: String
    let body: String
    let variantID: String
    let destination: NotificationDestination
    let threadID: String
    let interruption: Interruption

    static func identifier(for dedupeKey: String) -> String { "stopswiping.\(dedupeKey)" }
}

/// Decides which notifications should be pending right now. A pure function
/// of its inputs: eligibility, completed actions, consent, dedupe, cooldowns,
/// quiet hours in the user's time zone, priorities and the weekly budget all
/// live here, so nothing else has to know the rules.
struct NotificationPlanner {
    var policy: NotificationPolicy = .standard
    /// Carries the user's time zone.
    var calendar: Calendar = .autoupdatingCurrent
    var installID: String

    private struct Candidate {
        let kind: NotificationKind
        let dedupeKey: String
        var trigger: Date
        var flavor: String? = nil
        var values: [String: String] = [:]
        let destination: NotificationDestination
        var threadID: String? = nil
    }

    func plan(context: NotificationContext, ledger: NotificationLedger,
              preferences: NotificationPreferences, now: Date) -> [PlannedNotification] {
        guard context.permission == .authorized else { return [] }
        let quietHours = QuietHours(preferences)

        // Eligibility, preferences, dedupe and cooldowns.
        var candidates = candidates(context, ledger: ledger, now: now).filter { candidate in
            preferences.allows(candidate.kind) && !candidate.kind.isInAppOnly && !candidate.kind.isServerSent
                && !ledger.hasDelivered(candidate.dedupeKey)
        }

        // Timing.
        for index in candidates.indices {
            var fire = max(candidates[index].trigger, now.addingTimeInterval(policy.minimumLead))
            let kind = candidates[index].kind
            if let last = ledger.lastDelivery(of: kind), kind.cooldown > 0 {
                fire = max(fire, last.addingTimeInterval(kind.cooldown))
            }
            if kind.category.isNudge {
                fire = max(fire, context.lastActiveAt.addingTimeInterval(policy.activityGrace))
            }
            candidates[index].trigger = shiftedOutOfQuietHours(fire, kind: kind, key: candidates[index].dedupeKey,
                                                               quietHours: quietHours)
        }

        // Priority first, then the soonest.
        candidates.sort { ($0.kind.priority, $0.trigger) < ($1.kind.priority, $1.trigger) }

        // The weekly budget for nudges.
        var nudgeTimes = ledger.nudgeDeliveries(since: now.addingTimeInterval(-7 * NotificationPolicy.day))
        var accepted: [Candidate] = []
        for var candidate in candidates {
            if candidate.kind.category.isNudge {
                guard let slot = budgetSlot(from: candidate.trigger, taken: nudgeTimes, kind: candidate.kind,
                                            key: candidate.dedupeKey, quietHours: quietHours),
                      slot <= now.addingTimeInterval(policy.horizon) else { continue }
                candidate.trigger = slot
                nudgeTimes.append(slot)
            }
            accepted.append(candidate)
        }

        return accepted.compactMap { candidate in
            let slot = NotificationCopy.Slot(candidate.kind, candidate.flavor)
            guard let copy = NotificationCopy.variant(for: slot, installID: installID,
                                                      sendIndex: ledger.deliveryCount(of: candidate.kind),
                                                      values: candidate.values) else { return nil }
            let passive = candidate.kind.category == .transactional
                && quietHours?.contains(candidate.trigger, calendar: calendar) == true
            return PlannedNotification(identifier: PlannedNotification.identifier(for: candidate.dedupeKey),
                                       kind: candidate.kind, dedupeKey: candidate.dedupeKey,
                                       fireDate: candidate.trigger, title: copy.title, body: copy.body,
                                       variantID: copy.template.id, destination: candidate.destination,
                                       threadID: candidate.threadID ?? candidate.kind.category.rawValue,
                                       interruption: passive ? .passive : .active)
        }.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Eligibility

    private func candidates(_ context: NotificationContext, ledger: NotificationLedger, now: Date) -> [Candidate] {
        var result: [Candidate] = []
        let day = NotificationPolicy.day

        // A second, final reminder for a required action, then silence.
        func twoStep(_ kind: NotificationKind, prefix: String, first: Date, repeatAfter: TimeInterval,
                     flavor: String? = nil, destination: NotificationDestination) {
            let sent = ledger.deliveries(withKeyPrefix: prefix)
            switch sent.count {
            case 0: result.append(Candidate(kind: kind, dedupeKey: prefix + "1", trigger: first, flavor: flavor,
                                            destination: destination))
            case 1: result.append(Candidate(kind: kind, dedupeKey: prefix + "2",
                                            trigger: sent[0].fireDate.addingTimeInterval(repeatAfter), flavor: flavor,
                                            destination: destination))
            default: break
            }
        }

        // 6, 7: consent. Required before anything matching-related.
        let noticed = context.privacyIssueNoticedAt ?? now
        switch context.profileConsent {
        case .missing where context.onboardingCompleted && context.hasDisplayName && !context.isUnderageLocked:
            twoStep(.privacyRequired, prefix: "privacy_required.\(PrivacyConsentKind.profile.version).",
                    first: noticed.addingTimeInterval(policy.privacyRequiredFirst),
                    repeatAfter: policy.privacyRepeatAfter, destination: .privacy(.profile))
        case .outdated where !context.isUnderageLocked:
            twoStep(.privacyUpdated, prefix: "privacy_updated.profile.\(PrivacyConsentKind.profile.version).",
                    first: noticed.addingTimeInterval(policy.privacyUpdatedFirst),
                    repeatAfter: policy.privacyRepeatAfter, flavor: "profile", destination: .privacy(.profile))
        case .current where context.matchingConsent == .outdated && context.matchingConfigured:
            twoStep(.privacyUpdated, prefix: "privacy_updated.matching.\(PrivacyConsentKind.matching.version).",
                    first: noticed.addingTimeInterval(policy.privacyUpdatedFirst),
                    repeatAfter: policy.privacyRepeatAfter, flavor: "matching", destination: .privacy(.matching))
        default: break
        }
        let consentOK = context.consentComplete

        // A1: matching paused because preferences are missing.
        if consentOK, context.matchingSetupNeedsAttention, !context.isUnderageLocked {
            let since = context.setupIssueNoticedAt ?? now
            result.append(Candidate(kind: .matchingSetupIncomplete,
                                    dedupeKey: "matching_setup_incomplete.\(stamp(since))",
                                    trigger: since.addingTimeInterval(policy.setupAttentionAfter),
                                    destination: .autoMatching))
        }

        // 12: questionnaire started, not finished. Twice per absence.
        if context.onboardingStarted, !context.onboardingCompleted, !context.isUnderageLocked {
            let prefix = "onboarding_incomplete.\(stamp(context.lastActiveAt))."
            let sent = ledger.deliveries(withKeyPrefix: prefix)
            let trigger: Date? = switch sent.count {
            case 0: context.lastActiveAt.addingTimeInterval(policy.onboardingFirst)
            case 1: sent[0].fireDate.addingTimeInterval(policy.onboardingRepeatAfter)
            default: nil
            }
            let shielded = trigger.flatMap { trigger in
                context.earlyAccessReminderAt.map { abs($0.timeIntervalSince(trigger)) < policy.earlyAccessReminderShield }
            } ?? false
            if let trigger, !shielded {
                let percent = Int((context.onboardingProgress * 100).rounded())
                result.append(Candidate(kind: .onboardingIncomplete, dedupeKey: prefix + "\(sent.count + 1)",
                                        trigger: trigger,
                                        values: (10...95).contains(percent) ? ["percent": "\(percent)"] : [:],
                                        destination: .onboarding))
            }
        }

        // Everything below needs the consent matching depends on.
        guard consentOK else { return result }

        // The conversation of the active match.
        if context.hasAccount, let chat = context.conversation, chat.isLoaded {
            let id = chat.matchID.uuidString.lowercased()
            let thread = "chat.\(id)"
            if chat.unsentCount > 0 {
                // A2: queued messages only send while the app is open.
                result.append(Candidate(kind: .messageNotSent, dedupeKey: "message_not_sent.\(id).\(chat.unsentKey)",
                                        trigger: now.addingTimeInterval(policy.unsentMessageAfter),
                                        destination: .chat, threadID: thread))
            }
            if let unreadAt = chat.oldestUnreadAt {
                // 5: unread, so the chat hasn't been opened since it arrived.
                result.append(Candidate(kind: .messageUnanswered, dedupeKey: "message_unanswered.\(id).\(stamp(unreadAt))",
                                        trigger: unreadAt.addingTimeInterval(policy.unansweredAfter),
                                        destination: .chat, threadID: thread))
            } else if chat.messagesFromMe + chat.messagesFromPartner == 0 {
                // 5b: nobody has said hello yet.
                result.append(Candidate(kind: .matchNoConversation, dedupeKey: "match_no_conversation.\(id)",
                                        trigger: chat.matchedAt.addingTimeInterval(policy.noConversationAfter),
                                        destination: .chat, threadID: thread))
            } else if chat.messagesFromMe > 0, chat.messagesFromPartner > 0, let last = chat.lastMessageAt {
                // 4: a real conversation that stalled. Sooner when the ball
                // is in this user's court; double-texting can wait longer.
                let after = chat.lastMessageFromPartner ? policy.quietConversationAfter : 2 * policy.quietConversationAfter
                result.append(Candidate(kind: .conversationQuiet, dedupeKey: "conversation_quiet.\(id).\(stamp(last))",
                                        trigger: last.addingTimeInterval(after), destination: .chat, threadID: thread))
            }
        }

        // With a match you're matched with that one person: no matchmaking nudges.
        guard context.matchingAvailable, context.conversation == nil else { return result }

        // 8: a week after accepting the terms, no comparison yet.
        if let accepted = context.profileConsent.acceptedAt, context.lastCompatibilityCheckAt == nil,
           !context.hasEverCheckedCompatibility {
            result.append(Candidate(kind: .firstMatchmaking, dedupeKey: "first_matchmaking",
                                    trigger: accepted.addingTimeInterval(policy.firstMatchmakingAfter), destination: .share))
        }

        // 10: a month since the last comparison.
        if let last = context.lastCompatibilityCheckAt {
            result.append(Candidate(kind: .compatibilityMonthly, dedupeKey: "compatibility_monthly.\(stamp(last))",
                                    trigger: last.addingTimeInterval(policy.compatibilityMonthlyAfter), destination: .share))
        }

        // 9: high bar, auto-matching on for 30 days, no match since.
        var standardsTrigger: Date?
        if context.autoMatchingEnabled, let since = context.autoMatchingEnabledSince,
           context.minimumMatchPercent >= policy.standardsMinimumScore,
           context.lastMatchAt.map({ $0 < since }) ?? true {
            var period = max(1, Int(now.timeIntervalSince(since) / policy.standardsPeriod))
            if ledger.hasDelivered("lower_standards.\(stamp(since)).\(period)") { period += 1 }
            let trigger = since.addingTimeInterval(Double(period) * policy.standardsPeriod)
            standardsTrigger = trigger
            result.append(Candidate(kind: .lowerStandards, dedupeKey: "lower_standards.\(stamp(since)).\(period)",
                                    trigger: trigger, destination: .autoMatching))
        }

        // 11: auto-matching keeps working while the user is away. Never
        // within two weeks of the standards nudge, sent or coming.
        if context.autoMatchingEnabled {
            let trigger = context.lastActiveAt.addingTimeInterval(policy.idleAfter)
            let nearStandards = [standardsTrigger, ledger.lastDelivery(of: .lowerStandards)].compactMap { $0 }
                .contains { abs($0.timeIntervalSince(trigger)) < 14 * day }
            if !nearStandards {
                result.append(Candidate(kind: .autoMatchingIdle, dedupeKey: "auto_matching_idle.\(stamp(context.lastActiveAt))",
                                        trigger: trigger, destination: .profile))
            }
        }
        return result
    }

    // MARK: - Timing

    /// Moves a non-transactional notification out of quiet hours, spread
    /// over the first minutes after they end so not everything lands at once.
    private func shiftedOutOfQuietHours(_ date: Date, kind: NotificationKind, key: String,
                                        quietHours: QuietHours?) -> Date {
        guard let quietHours, kind.category != .transactional, quietHours.contains(date, calendar: calendar) else {
            return date
        }
        let end = quietHours.nextAllowed(after: date, calendar: calendar)
        let spread = Int(NotificationCopy.fnv1a(key) % UInt64(max(policy.quietHoursSpreadMinutes, 1)))
        return end.addingTimeInterval(Double(spread) * 60)
    }

    /// The first moment from `start` that keeps nudges at least
    /// `minimumNudgeGap` apart and never more than the weekly budget within
    /// seven days of each other.
    private func budgetSlot(from start: Date, taken: [Date], kind: NotificationKind, key: String,
                            quietHours: QuietHours?) -> Date? {
        let week = 7 * NotificationPolicy.day
        var slot = start
        for _ in 0..<12 {
            if let clash = taken.filter({ abs($0.timeIntervalSince(slot)) < policy.minimumNudgeGap }).max() {
                slot = shiftedOutOfQuietHours(clash.addingTimeInterval(policy.minimumNudgeGap), kind: kind, key: key,
                                              quietHours: quietHours)
                continue
            }
            let nearby = taken.filter { abs($0.timeIntervalSince(slot)) < week }.sorted()
            if nearby.count >= policy.nudgesPerWeek, let oldest = nearby.first {
                slot = shiftedOutOfQuietHours(max(slot, oldest.addingTimeInterval(week)), kind: kind, key: key,
                                              quietHours: quietHours)
                continue
            }
            return slot
        }
        return nil
    }

    /// Seconds since 1970, for dedupe keys tied to a moment.
    private func stamp(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }
}
