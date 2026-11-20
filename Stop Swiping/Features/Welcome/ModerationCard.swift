import SwiftUI

/// Reports against this account, on the home screen where automatic
/// matching would be. A warning shows until it is read; a 7-day block or a
/// ban shows for as long as it lasts, while the light holds the lock and
/// automatic matching is switched off and hidden. The profile and the
/// personality tests stay open.
struct ModerationCard: View {
    let status: ModerationStatus
    /// A strike this phone has not acknowledged yet.
    let isUnread: Bool
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.isLocked(status) ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(OnboardingTheme.pink)
                    .accessibilityHidden(true)
                Text(Self.title(status))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Self.message(status))
                .font(.footnote)
                .foregroundStyle(OnboardingTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if Self.isLocked(status) {
                Text(L10n("Automatic matching is off while this lasts. You can still view your personality and edit your profile."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isUnread {
                Button(L10n("I understand"), action: onAcknowledge)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.cyan)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moderation.acknowledge")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, isUnread ? 4 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MatchingActionSurface(isOn: true))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moderation.card")
    }

    /// Blocked or banned: no automatic matching, and the light is a lock.
    static func isLocked(_ status: ModerationStatus, now: Date = Date()) -> Bool {
        status.banned || status.isSuspended(now: now)
    }

    /// Whether the home screen shows the card at all.
    static func isShown(_ status: ModerationStatus?, isUnread: Bool) -> Bool {
        guard let status else { return false }
        return isLocked(status) || isUnread
    }

    static func title(_ status: ModerationStatus) -> String {
        if status.banned { return L10n("Your account is banned") }
        if status.isSuspended() { return L10n("Your account is blocked for 7 days") }
        return L10n("You were reported")
    }

    static func message(_ status: ModerationStatus) -> String {
        if status.banned {
            return L10n("You were reported three times. Your account can no longer match or chat. You can still delete it from your profile.")
        }
        if status.isSuspended(), let until = status.suspendedUntil {
            let date = until.formatted(.dateTime.day().month(.wide).hour().minute().locale(AppLocale.current))
            return L10n("You were reported a second time. Until \(date) you can’t match or chat. A third report bans your account.")
        }
        return L10n("Someone you matched with reported you. This is a warning: a second report blocks you for 7 days, a third bans your account.")
    }
}
