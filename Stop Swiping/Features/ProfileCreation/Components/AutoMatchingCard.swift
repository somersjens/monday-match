import SwiftUI

/// The home screen's auto matching switch and entry to its setup flow.
struct AutoMatchingCard: View {
    @ObservedObject var viewModel: ProfileCreationViewModel
    let onOpenSettings: () -> Void

    @State private var resumeFailed = false

    var body: some View {
        let settings = viewModel.state.autoMatching
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n("Join auto matching"))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.primaryText)
                    Text(settings.isEnabled
                         ? L10n("On · at least \(settings.minimumMatchPercent)% match")
                         : L10n("Let us propose matches for you."))
                        .font(.footnote)
                        .foregroundStyle(OnboardingTheme.secondaryText)
                        .contentTransition(.opacity)
                }
                .accessibilityHidden(true)

                Spacer(minLength: 8)

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
            .padding(.vertical, 14)

            if resumeFailed {
                Text(L10n("Auto matching couldn’t be saved. Try again."))
                    .font(.footnote)
                    .foregroundStyle(OnboardingTheme.pink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if settings.isEnabled || settings.hasCompletedSetup {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 0.5)
                    .padding(.leading, 16)

                Button { onOpenSettings() } label: {
                    HStack {
                        Text(L10n("Auto matching settings"))
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(OnboardingTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AutoMatchingSettingsButtonStyle())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [OnboardingTheme.blue.opacity(0.20), OnboardingTheme.violet.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [OnboardingTheme.cyan.opacity(settings.isEnabled ? 0.55 : 0.25), OnboardingTheme.violet.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut(duration: 0.25), value: settings.isEnabled)
    }

    private var icon: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LinearGradient(
                colors: [OnboardingTheme.cyan, OnboardingTheme.violet],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.12))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct AutoMatchingSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.08 : 0))
    }
}
