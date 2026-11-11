import SwiftUI

struct OnboardingProgressHeader: View {
    let title: String
    let progress: Double
    let showsBackButton: Bool
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .opacity(showsBackButton ? 1 : 0)
                .disabled(!showsBackButton)
                .accessibilityHidden(!showsBackButton)

                Spacer()

                Text(title)
                    .font(AppTypography.headline)
                    .multilineTextAlignment(.center)

                Spacer()

                Color.clear
                    .frame(width: 44, height: 44)
            }

            ProgressView(value: progress)
                .tint(AppColors.accent)
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.top, AppSpacing.small)
        .padding(.bottom, AppSpacing.medium)
        .background(AppColors.background)
    }
}
