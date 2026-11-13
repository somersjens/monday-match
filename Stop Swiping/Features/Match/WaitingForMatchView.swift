import SwiftUI

struct WaitingForMatchView: View {
    var body: some View {
        VStack(spacing: AppSpacing.xLarge) {
            Spacer()

            Image(systemName: "heart.circle")
                .font(.system(size: 72))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: AppSpacing.small) {
                Text(L10n("No active result"))
                    .font(AppTypography.title)

                Text(
                    L10n("Join a weekly round from the dashboard. Your next result will appear here after Sunday’s reveal.")
                )
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
                .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(AppSpacing.large)
    }
}
