import SwiftUI

struct ProfileBasicsStepView: View {
    @Binding var draft: ProfileDraft

    private let maximumBioLength = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(L10n("Introduce yourself"))
                        .font(AppTypography.title)

                    Text(
                        L10n("Use a first name or nickname and write a short bio that gives your match something real to respond to.")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(L10n("Display name"))
                        .font(AppTypography.headline)

                    TextField(
                        L10n("Your name"),
                        text: $draft.displayName
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(AppSpacing.medium)
                    .background(AppColors.secondaryBackground)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }

                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack {
                        Text(L10n("Bio"))
                            .font(AppTypography.headline)

                        Spacer()

                        Text("\(draft.bio.count)/\(maximumBioLength)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryForeground)
                    }

                    TextEditor(text: $draft.bio)
                        .frame(minHeight: 180)
                        .padding(AppSpacing.small)
                        .scrollContentBackground(.hidden)
                        .background(AppColors.secondaryBackground)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )
                        .onChange(of: draft.bio) { _, newValue in
                            if newValue.count > maximumBioLength {
                                draft.bio = String(
                                    newValue.prefix(maximumBioLength)
                                )
                            }
                        }

                    Text(
                        L10n("Minimum 20 characters. Avoid sharing your home address, phone number or other sensitive details.")
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
                }
            }
            .padding(AppSpacing.large)
        }
    }
}

#Preview {
    ProfileBasicsStepView(
        draft: .constant(ProfileDraft())
    )
}
