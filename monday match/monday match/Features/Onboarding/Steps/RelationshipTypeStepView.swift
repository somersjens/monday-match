import SwiftUI

struct RelationshipTypeStepView: View {
    let selectedTypes: Set<RelationshipType>
    let onToggle: (RelationshipType) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("What kind of relationship are you looking for?")
                        .font(AppTypography.title)

                    Text(
                        "Select every option you are genuinely open to. These preferences will be treated as an important matching filter."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                VStack(spacing: AppSpacing.small) {
                    ForEach(RelationshipType.allCases) { type in
                        Button {
                            onToggle(type)
                        } label: {
                            HStack(alignment: .top, spacing: AppSpacing.medium) {
                                Image(systemName: type.symbol)
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 32)
                                    .foregroundStyle(AppColors.accent)

                                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                                    Text(type.title)
                                        .font(AppTypography.body.weight(.semibold))

                                    Text(type.description)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.secondaryForeground)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(
                                    systemName: selectedTypes.contains(type)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(
                                    selectedTypes.contains(type)
                                        ? AppColors.accent
                                        : AppColors.secondaryForeground
                                )
                            }
                            .foregroundStyle(AppColors.foreground)
                            .padding(AppSpacing.medium)
                            .background(
                                selectedTypes.contains(type)
                                    ? AppColors.accent.opacity(0.10)
                                    : AppColors.secondaryBackground
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 20,
                                    style: .continuous
                                )
                                .stroke(
                                    selectedTypes.contains(type)
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
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

#Preview {
    RelationshipTypeStepView(
        selectedTypes: [.monogamous],
        onToggle: { _ in }
    )
}
