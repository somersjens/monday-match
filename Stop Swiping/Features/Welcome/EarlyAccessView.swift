import SwiftUI

struct EarlyAccessView: View {
    let onClaimAccess: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                header
                pricingCard
                communityMessage

                PrimaryButton(
                    title: L10n("Claim free lifetime access"),
                    action: onClaimAccess
                )

                Text(L10n("No payment details required."))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
            }
            .padding(AppSpacing.large)
        }
        .background(AppColors.background)
        .navigationTitle(L10n("Early access"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: AppSpacing.medium) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .accessibilityHidden(true)

            Text(L10n("No matches without people."))
                .font(AppTypography.title)
                .multilineTextAlignment(.center)

            Text(
                L10n("Join as an early adopter and help build the first thoughtful matching community.")
            )
            .font(AppTypography.body)
            .foregroundStyle(AppColors.secondaryForeground)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
        }
    }

    private var pricingCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    Text(L10n("Early adopter"))
                        .font(AppTypography.headline)

                    Spacer()

                    Text(L10n("LIMITED"))
                        .font(AppTypography.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.small) {
                    Text("€0")
                        .font(.system(size: 52, weight: .bold, design: .rounded))

                    Text("lifetime")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryForeground)
                }

                Divider()

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    benefit(L10n("Join future matching rounds"))
                    benefit(L10n("Receive one thoughtful match at a time"))
                    benefit(L10n("Keep early-adopter access for life"))
                }

                HStack {
                    Text(L10n("Future lifetime price"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)

                    Spacer()

                    Text("€49.99")
                        .font(AppTypography.body.weight(.semibold))
                        .strikethrough()
                        .foregroundStyle(AppColors.secondaryForeground)
                }
            }
        }
    }

    private var communityMessage: some View {
        Text(
            L10n("Your free access is attached to your account after registration. It is not a subscription and does not renew.")
        )
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.secondaryForeground)
        .multilineTextAlignment(.center)
        .padding(.horizontal, AppSpacing.medium)
    }

    private func benefit(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(AppTypography.body)
            .foregroundStyle(AppColors.foreground)
            .symbolRenderingMode(.hierarchical)
    }
}

#Preview {
    NavigationStack {
        EarlyAccessView(onClaimAccess: {})
    }
}
