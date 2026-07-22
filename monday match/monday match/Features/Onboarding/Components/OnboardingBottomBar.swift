import SwiftUI

struct OnboardingBottomBar: View {
    let buttonTitle: String
    let validationMessage: String?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            if let validationMessage, !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(
                title: buttonTitle,
                isDisabled: !isEnabled,
                action: action
            )
        }
        .padding(AppSpacing.large)
        .background(.ultraThinMaterial)
    }
}
