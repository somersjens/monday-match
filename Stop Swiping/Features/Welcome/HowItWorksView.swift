import SwiftUI

struct HowItWorksView: View {
    let onContinue: () -> Void

    private let steps = HowItWorksStep.defaults

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                header

                VStack(spacing: AppSpacing.medium) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        HowItWorksCard(
                            number: index + 1,
                            step: step,
                            showsConnector: index < steps.count - 1
                        )
                    }
                }

                safetyNote

                PrimaryButton(
                    title: L10n("Claim early access"),
                    action: onContinue
                )
            }
            .padding(AppSpacing.large)
        }
        .background(AppColors.background)
        .navigationTitle(L10n("How it works"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(L10n("Less swiping.\nMore intention."))
                .font(AppTypography.title)

            Text(
                L10n("Complete your profile once, choose when you want to join, and receive at most one carefully selected match.")
            )
            .font(AppTypography.body)
            .foregroundStyle(AppColors.secondaryForeground)
            .lineSpacing(4)
        }
    }

    private var safetyNote: some View {
        AppCard {
            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(L10n("Meet safely"))
                        .font(AppTypography.headline)

                    Text(
                        L10n("Take your time, keep personal details private at first, and meet in a public place.")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                }
            }
        }
    }
}

private struct HowItWorksCard: View {
    let number: Int
    let step: HowItWorksStep
    let showsConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 42, height: 42)

                    Text("\(number)")
                        .font(AppTypography.headline)
                        .foregroundStyle(.white)
                }

                if showsConnector {
                    Rectangle()
                        .fill(AppColors.divider)
                        .frame(width: 1, height: 64)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Label {
                    Text(step.title)
                        .font(AppTypography.headline)
                } icon: {
                    Image(systemName: step.symbol)
                        .foregroundStyle(AppColors.accent)
                }

                Text(step.description)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(3)
            }
            .padding(.top, AppSpacing.xSmall)

            Spacer(minLength: 0)
        }
    }
}

private struct HowItWorksStep: Identifiable {
    var id: String { symbol }
    let symbol: String
    let title: String
    let description: String

    static var defaults: [HowItWorksStep] { [
        .init(
            symbol: "person.crop.circle.badge.checkmark",
            title: L10n("Complete your profile"),
            description: L10n("Share what matters to you and what you hope to find in a partner.")
        ),
        .init(
            symbol: "checkmark.circle",
            title: L10n("Join a matching round"),
            description: L10n("Opt in or out each week. Your profile is only considered when you choose to participate.")
        ),
        .init(
            symbol: "function",
            title: L10n("We run the numbers"),
            description: L10n("Saturday night, compatible participants are compared and paired without endless browsing.")
        ),
        .init(
            symbol: "bell.badge",
            title: L10n("Discover your match"),
            description: L10n("On Sunday, we let you know whether a match above the minimum compatibility threshold was found.")
        ),
        .init(
            symbol: "message",
            title: L10n("Start a conversation"),
            description: L10n("View your match’s profile, chat, and decide at your own pace whether you want to meet.")
        )
    ] }
}

#Preview {
    NavigationStack {
        HowItWorksView(onContinue: {})
    }
}
