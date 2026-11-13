import SwiftUI

struct SelectableOptionCard: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.medium) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 32)

                Text(title)
                    .font(AppTypography.body.weight(.semibold))

                Spacer()

                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? AppColors.accent
                        : AppColors.secondaryForeground
                )
            }
            .foregroundStyle(AppColors.foreground)
            .padding(AppSpacing.medium)
            .background(
                isSelected
                    ? AppColors.accent.opacity(0.10)
                    : AppColors.secondaryBackground
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? AppColors.accent
                        : Color.clear,
                    lineWidth: 1.5
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }
}
