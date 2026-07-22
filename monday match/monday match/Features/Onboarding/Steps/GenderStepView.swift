import SwiftUI

struct GenderStepView: View {
    @Binding var draft: ProfileDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("How do you identify?")
                        .font(AppTypography.title)

                    Text(
                        "Choose the option that fits you best. You can change this later."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                VStack(spacing: AppSpacing.small) {
                    ForEach(GenderIdentity.allCases) { gender in
                        SelectableOptionCard(
                            title: gender.title,
                            symbol: gender.symbol,
                            isSelected: draft.gender == gender,
                            action: {
                                draft.gender = gender

                                if gender != .selfDescribed {
                                    draft.selfDescribedGender = ""
                                }
                            }
                        )
                    }
                }

                if draft.gender == .selfDescribed {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text("Describe your gender")
                            .font(AppTypography.headline)

                        TextField(
                            "Enter your description",
                            text: $draft.selfDescribedGender
                        )
                        .textInputAutocapitalization(.sentences)
                        .padding(AppSpacing.medium)
                        .background(AppColors.secondaryBackground)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(AppSpacing.large)
            .animation(.easeInOut, value: draft.gender)
        }
    }
}

#Preview {
    GenderStepView(
        draft: .constant(ProfileDraft())
    )
}
