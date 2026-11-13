import SwiftUI

struct NoMatchView: View {
    let result: MatchResult

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                Spacer(minLength: AppSpacing.xLarge)

                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.10))
                        .frame(width: 150, height: 150)

                    Image(systemName: "heart.slash")
                        .font(.system(size: 54))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(spacing: AppSpacing.medium) {
                    Text(L10n("No strong match this week"))
                        .font(AppTypography.title)
                        .multilineTextAlignment(.center)

                    Text(
                        L10n("We did not find a pairing above the 60% compatibility threshold. That is better than forcing a weak match.")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(L10n("What happens next"))
                            .font(AppTypography.headline)

                        Text(
                            L10n("Your profile stays ready. Review your preferences, update anything that changed, and opt in again for the next round.")
                        )
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

#Preview {
    NavigationStack {
        NoMatchView(result: .noMatchMock)
    }
}
