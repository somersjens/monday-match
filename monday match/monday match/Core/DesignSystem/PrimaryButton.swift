import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }

                Text(title)
                    .font(AppTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.medium)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .disabled(isDisabled || isLoading)
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: AppSpacing.medium) {
        PrimaryButton(title: "Get started", action: {})
        PrimaryButton(title: "Loading", isLoading: true, action: {})
    }
    .padding()
}
