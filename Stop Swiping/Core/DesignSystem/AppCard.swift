import SwiftUI

struct AppCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

#Preview {
    AppCard {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(L10n("Next matching round"))
                .font(AppTypography.headline)

            Text(L10n("Sunday at 10:00"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
        }
    }
    .padding()
}
