import SwiftUI

/// The home screen's auto matching switch and entry to its setup flow.
struct AutoMatchingCard: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onOpenSettings: () -> Void

    @State private var resumeFailed = false

    var body: some View {
        let settings = viewModel.state.autoMatching
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onOpenSettings) {
                    HStack(spacing: 4) {
                        Text(L10n("Join auto matching"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if settings.isEnabled {
                            Text(verbatim: "· \(settings.minimumMatchPercent)%")
                                .foregroundStyle(OnboardingTheme.secondaryText)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n("Auto matching settings"))

                GlowToggle(isOn: settings.isEnabled, label: L10n("Join auto matching")) {
                    resumeFailed = false
                    if settings.isEnabled {
                        viewModel.leaveAutoMatching()
                    } else if viewModel.canResumeAutoMatching {
                        resumeFailed = !viewModel.resumeAutoMatching()
                    } else {
                        onOpenSettings()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: OnboardingTheme.buttonHeight)

            if resumeFailed {
                Text(L10n("Auto matching couldn’t be saved. Try again."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .modifier(MatchingActionSurface(isOn: settings.isEnabled))
        .animation(.easeInOut(duration: 0.25), value: settings.isEnabled)
    }
}

/// The switch opens sign-up; it is only on once authentication succeeds.
struct AccountCreationCard: View {
    let onCreateAccount: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onCreateAccount) {
                Text(L10n("Create your account"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)

            GlowToggle(isOn: false, label: L10n("Create your account"), action: onCreateAccount)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: OnboardingTheme.buttonHeight)
        .modifier(MatchingActionSurface(isOn: false))
    }
}

/// Asks for notification permission. The switch slides on while the system
/// prompt is open; the decision itself then replaces this card.
struct NotificationPermissionCard: View {
    let isRequesting: Bool
    let onAllow: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onAllow) {
                Text(L10n("Allow notifications"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            GlowToggle(isOn: isRequesting, label: L10n("Allow notifications"), action: onAllow)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: OnboardingTheme.buttonHeight)
        .modifier(MatchingActionSurface(isOn: isRequesting))
        .disabled(isRequesting)
    }
}

private struct MatchingActionSurface: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [OnboardingTheme.blue.opacity(0.20), OnboardingTheme.violet.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [OnboardingTheme.cyan.opacity(isOn ? 0.55 : 0.25), OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}
