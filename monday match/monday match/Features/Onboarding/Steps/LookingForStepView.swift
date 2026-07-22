import SwiftUI

struct LookingForStepView: View {
    let selectedGenders: Set<GenderIdentity>
    let onToggle: (GenderIdentity) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("Who would you like to meet?")
                        .font(AppTypography.title)

                    Text(
                        "You can select more than one option. A match is only possible when both people’s preferences are compatible."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                VStack(spacing: AppSpacing.small) {
                    ForEach(GenderIdentity.allCases) { gender in
                        SelectableOptionCard(
                            title: gender.title,
                            symbol: gender.symbol,
                            isSelected: selectedGenders.contains(gender),
                            action: {
                                onToggle(gender)
                            }
                        )
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

#Preview {
    LookingForStepView(
        selectedGenders: [.woman, .nonBinary],
        onToggle: { _ in }
    )
}
