import SwiftUI

struct PlaceholderScreen: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(title)
                .font(AppTypography.title)

            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.large)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PlaceholderScreen(
            title: L10n("Dashboard"),
            message: L10n("Your next matching round will appear here.")
        )
    }
}
