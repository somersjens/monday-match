import SwiftUI

struct InterestsStepView: View {
    let selectedInterests: Set<ProfileInterest>
    let onToggle: (ProfileInterest) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.small),
        GridItem(.flexible(), spacing: AppSpacing.small)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(L10n("What are you into?"))
                        .font(AppTypography.title)

                    Text(
                        L10n("Choose at least three interests. These help create conversation starters and can contribute to compatibility later.")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                LazyVGrid(
                    columns: columns,
                    spacing: AppSpacing.small
                ) {
                    ForEach(ProfileInterest.allCases) { interest in
                        InterestTile(
                            interest: interest,
                            isSelected: selectedInterests.contains(interest),
                            action: {
                                onToggle(interest)
                            }
                        )
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

private struct InterestTile: View {
    let interest: ProfileInterest
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.small) {
                Image(systemName: interest.symbol)
                    .font(.system(size: 26, weight: .semibold))

                Text(interest.title)
                    .font(AppTypography.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 110)
            .foregroundStyle(
                isSelected
                    ? AppColors.accent
                    : AppColors.foreground
            )
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

#Preview {
    InterestsStepView(
        selectedInterests: [.music, .travel, .movies],
        onToggle: { _ in }
    )
}
