import SwiftUI

/// Reports against this account, on the home screen where automatic
/// matching would be. Each notice names the reason and says what the next
/// report would do. "Understood" is the main answer; "Object" opens the
/// objection screen, for every report, as long as no objection was made to
/// it yet. A warning shows until it is read, a pending objection until it is
/// decided, a 7-day block or a ban for as long as it lasts (the light holds
/// the lock and automatic matching is switched off and hidden). The profile
/// and the personality tests stay open.
struct ModerationCard: View {
    let status: ModerationStatus
    /// A strike this phone has not acknowledged yet.
    let isUnread: Bool
    /// The outcome of an objection this phone has not acknowledged yet.
    let result: ModerationStatus.ObjectionResult?
    let onAcknowledge: () -> Void
    let onObject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(OnboardingTheme.pink)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(message)
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showsResultOnly == false {
                if Self.isLocked(status) {
                    Text(L10n("Automatic matching is off while this lasts. You can still view your personality and edit your profile."))
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let objectionLine {
                    Label(objectionLine, systemImage: status.latestReport?.objection == .pending ? "hourglass" : "xmark.circle")
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("moderation.objectionState")
                }
            }
            if showsUnderstood || showsObject {
                VStack(spacing: 0) {
                    if showsUnderstood {
                        Button(L10n("Understood"), action: onAcknowledge)
                            .buttonStyle(GlowButtonStyle())
                            .accessibilityIdentifier("moderation.acknowledge")
                    }
                    if showsObject {
                        Button(L10n("Object"), action: onObject)
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityHint(L10n("Explain in a message why this report is wrong."))
                            .accessibilityIdentifier("moderation.object")
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, showsObject ? 2 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MatchingActionSurface(isOn: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moderation.card")
    }

    // MARK: What shows

    /// An objection was decided and there is nothing else to say: the card
    /// only tells the outcome.
    private var showsResultOnly: Bool {
        result != nil && !isUnread && !Self.isLocked(status)
    }

    private var showsUnderstood: Bool { isUnread || result != nil }

    private var showsObject: Bool { !showsResultOnly && status.canObject }

    private var objectionLine: String? {
        switch status.latestReport?.objection {
        case .pending: L10n("Your objection was sent. You will see the outcome here.")
        case .rejected: L10n("Your objection was rejected. The report stands.")
        case .approved, nil: nil
        }
    }

    private var symbol: String {
        if showsResultOnly { return result?.decision == .approved ? "checkmark.seal.fill" : "xmark.seal.fill" }
        return Self.isLocked(status) ? "lock.fill" : "exclamationmark.triangle.fill"
    }

    private var title: String {
        if showsResultOnly, let result { return Self.resultTitle(result) }
        return Self.title(status)
    }

    private var message: String {
        if showsResultOnly, let result { return Self.resultMessage(result) }
        return Self.message(status)
    }

    // MARK: Rules

    /// Blocked or banned: no automatic matching, and the light is a lock.
    static func isLocked(_ status: ModerationStatus, now: Date = Date()) -> Bool {
        status.banned || status.isSuspended(now: now)
    }

    /// Whether the home screen shows the card at all.
    static func isShown(_ status: ModerationStatus?, isUnread: Bool, hasResult: Bool = false) -> Bool {
        guard let status else { return false }
        return isLocked(status) || isUnread || hasResult || status.latestReport?.objection == .pending
    }

    /// The reason in quotes, as the report screen names it.
    static func reasonText(_ code: String?) -> String {
        let title = code.flatMap(ReportReason.init(rawValue:))?.title ?? ReportReason.other.title
        return "“\(title)”"
    }

    static func title(_ status: ModerationStatus) -> String {
        if status.banned { return L10n("Your account is banned") }
        if status.isSuspended() { return L10n("Your account is blocked for 7 days") }
        return L10n("You were reported")
    }

    static func message(_ status: ModerationStatus) -> String {
        let reason = reasonText(status.latestReport?.reason)
        if status.banned {
            return L10n("Your account is permanently blocked because of \(reason). You can no longer match or chat. You can still delete your account from your profile.")
        }
        if status.isSuspended(), let until = status.suspendedUntil {
            let date = until.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLocale.current))
            return L10n("You are now blocked for 1 week because of \(reason), until \(date). The next time, your account will be blocked permanently.")
        }
        return L10n("You were reported because of \(reason). If this happens again, you can’t use your account for 7 days.")
    }

    static func resultTitle(_ result: ModerationStatus.ObjectionResult) -> String {
        result.decision == .approved ? L10n("Your objection was approved") : L10n("Your objection was rejected")
    }

    static func resultMessage(_ result: ModerationStatus.ObjectionResult) -> String {
        let reason = reasonText(result.reason)
        return result.decision == .approved
            ? L10n("The report because of \(reason) was withdrawn. It no longer counts against your account.")
            : L10n("The report because of \(reason) stands.")
    }
}
