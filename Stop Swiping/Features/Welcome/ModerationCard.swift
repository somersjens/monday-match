import SwiftUI

/// What the home screen says about reports: a report this person sent, a
/// report against them, or the outcome of their objection.
///
/// A notice that waits for an answer takes over the bottom controls: it
/// stands where automatic matching would be, and its own buttons
/// ("Understood", "Object") take the place of Adjust profile and My matches,
/// so nothing else competes with it. Once read, what is still true (an
/// objection under review, a block, a ban) stays as a status card in the
/// automatic matching card's place, with the profile buttons back below it.
/// Neither uses symbols: the words carry it, like the rest of the home screen.
struct ModerationNotice: Hashable {
    enum Kind: Hashable {
        /// A report against this account.
        case strike
        /// The decision on this person's objection.
        case objectionResult
        /// The report this person just sent about their match.
        case reportSent
    }

    let kind: Kind
    let title: String
    /// The report's reason, as the report screen names it.
    let reason: String?
    let message: String
    /// The way forward, in a paragraph of its own.
    var nextStep: String? = nil
    /// The report can still be objected to.
    let canObject: Bool
}

/// The home screen's part in a report.
enum ModerationHome: Equatable {
    /// Waits for "Understood": replaces the matching card and the profile buttons.
    case notice(ModerationNotice)
    /// Read but still true: replaces only the automatic matching card.
    case status(ModerationNotice)

    var notice: ModerationNotice? {
        if case .notice(let notice) = self { return notice }
        return nil
    }

    var status: ModerationNotice? {
        if case .status(let status) = self { return status }
        return nil
    }

    /// An objection's outcome comes first: it is about an older report than
    /// any new one. Then a report not read yet, then what still holds.
    static func resolve(_ status: ModerationStatus?, isUnread: Bool,
                        result: ModerationStatus.ObjectionResult?, now: Date = Date()) -> ModerationHome? {
        guard let status else { return nil }
        if let result { return .notice(ModerationCopy.result(result)) }
        if isUnread { return .notice(ModerationCopy.strike(status, now: now)) }
        if ModerationCopy.isLocked(status, now: now) || status.latestReport?.objection == .pending {
            return .status(ModerationCopy.status(status, now: now))
        }
        return nil
    }
}

// MARK: - Cards

/// A notice that waits for an answer, in the matching card's place. Its
/// buttons sit below it, where the profile buttons normally are.
struct ModerationNoticeCard: View {
    let notice: ModerationNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(notice.title)
                .font(.system(.headline))
                .foregroundStyle(OnboardingTheme.primaryText)
            if let reason = notice.reason {
                Text(L10n("Reason: \(reason)"))
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(OnboardingTheme.cyan)
                    .padding(.top, 3)
            }
            Text(notice.message)
                .font(.subheadline)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .padding(.top, 10)
            if let nextStep = notice.nextStep {
                Text(nextStep)
                    .font(.subheadline)
                    .foregroundStyle(OnboardingTheme.primaryText.opacity(0.9))
                    .padding(.top, 8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MatchingActionSurface(isOn: true))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("moderation.card")
    }
}

/// What still holds once the notice is read, exactly where the automatic
/// matching switch would be: an objection under review, a block, a ban.
/// A report that can still be objected to keeps its way to do so, in the
/// same quiet cyan the home screen's other cards use for their one action.
struct ModerationStatusCard: View {
    let status: ModerationNotice
    let onObject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                Text(status.message)
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: OnboardingTheme.buttonHeight - 20, alignment: .leading)
            .accessibilityElement(children: .combine)

            if status.canObject {
                Button(L10n("Object"), action: onObject)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.cyan)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityHint(L10n("Explain in a message why this report is wrong."))
                    .accessibilityIdentifier("moderation.object")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, status.canObject ? 2 : 10)
        .frame(maxWidth: .infinity, minHeight: OnboardingTheme.buttonHeight, alignment: .leading)
        .modifier(MatchingActionSurface(isOn: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moderation.status")
    }
}

// MARK: - Copy

/// Every sentence the home screen says about reports, in one place so the
/// notice, the status and the tests read the same words.
enum ModerationCopy {
    /// Blocked or banned: no automatic matching, and the light is a lock.
    static func isLocked(_ status: ModerationStatus, now: Date = Date()) -> Bool {
        status.banned || status.isSuspended(now: now)
    }

    static func reasonTitle(_ code: String?) -> String {
        (code.flatMap(ReportReason.init(rawValue:)) ?? .other).title
    }

    /// A day and a time, as "27 November at 14:00" reads in this language.
    static func until(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLocale.current))
    }

    // A report against this account

    static func strike(_ status: ModerationStatus, now: Date = Date()) -> ModerationNotice {
        let title: String
        let consequence: String
        if status.banned {
            title = L10n("Your account is permanently blocked")
            consequence = L10n("You were reported too often. You can no longer match or chat. You can still delete your account from your profile.")
        } else if status.isSuspended(now: now), let until = status.suspendedUntil {
            title = L10n("Your account is blocked for 7 days")
            consequence = L10n("You were reported again. Until \(Self.until(until)) you can’t match or chat. After a third report, your account is blocked permanently.")
        } else {
            title = L10n("You were reported")
            consequence = L10n("This is a warning. After a second report, your account is blocked for 7 days.")
        }
        return ModerationNotice(kind: .strike, title: title, reason: reasonTitle(status.latestReport?.reason),
                                message: consequence,
                                nextStep: status.canObject ? L10n("Not right? Object, and the report will be looked at again.") : nil,
                                canObject: status.canObject)
    }

    // The decision on an objection

    static func result(_ result: ModerationStatus.ObjectionResult) -> ModerationNotice {
        let approved = result.decision == .approved
        return ModerationNotice(
            kind: .objectionResult,
            title: approved ? L10n("Your objection was approved") : L10n("Your objection was rejected"),
            reason: reasonTitle(result.reason),
            message: approved
                ? L10n("The report was withdrawn and no longer counts against your account.")
                : L10n("The report was looked at again and stands. It keeps counting towards your account."),
            canObject: false)
    }

    // What still holds once read

    static func status(_ status: ModerationStatus, now: Date = Date()) -> ModerationNotice {
        let lock: String?
        if status.banned {
            lock = L10n("Your account is permanently blocked.")
        } else if status.isSuspended(now: now), let until = status.suspendedUntil {
            lock = L10n("Your account is blocked until \(Self.until(until)).")
        } else {
            lock = nil
        }

        if status.latestReport?.objection == .pending {
            let outcome = L10n("You’ll see the outcome here as soon as it has been looked at.")
            return ModerationNotice(kind: .strike, title: L10n("Objection under review"), reason: nil,
                                    message: lock.map { $0 + " " + outcome } ?? outcome, canObject: false)
        }
        if status.banned {
            return ModerationNotice(kind: .strike, title: L10n("Your account is permanently blocked"), reason: nil,
                                    message: L10n("You can no longer match or chat. You can still delete your account from your profile."),
                                    canObject: status.canObject)
        }
        let until = status.suspendedUntil.map(Self.until) ?? ""
        return ModerationNotice(kind: .strike, title: L10n("Blocked until \(until)"), reason: nil,
                                message: L10n("You can’t match or chat until then. You can still view your profile and personality."),
                                canObject: status.canObject)
    }

    // A report this person sent

    static func reportSent(name: String, reason: ReportReason, endedMatch: Bool) -> ModerationNotice {
        let received = L10n("Your report about \(name) was received. If \(name) objects, the report will be looked at again.")
        return ModerationNotice(kind: .reportSent, title: L10n("Thanks for your report"), reason: reason.title,
                                message: endedMatch ? L10n("Your match has been broken.") + " " + received : received,
                                canObject: false)
    }
}

/// A report this person sent, for the thanks on the home screen.
struct SentReport: Equatable {
    let name: String
    let reason: ReportReason
    let endedMatch: Bool
}
