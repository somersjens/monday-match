import SwiftUI

struct OnboardingReviewStepView: View {
    let draft: ProfileDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text(L10n("Your profile is taking shape."))
                        .font(AppTypography.title)

                    Text(
                        L10n("The next build block can add photo selection and a real profile preview.")
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                AppCard {
                    summaryRow(
                        title: L10n("Name"),
                        value: draft.displayName
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Age"),
                        value: "\(draft.age())"
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Gender"),
                        value: displayedGender
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Looking for"),
                        value: displayedInterests
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Relationship"),
                        value: displayedRelationshipTypes
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Interests"),
                        value: displayedProfileInterests
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Distance"),
                        value: L10n("\(draft.preferredRadiusKilometers) km")
                    )

                    Divider()

                    summaryRow(
                        title: L10n("Location"),
                        value: draft.matchLocation == nil
                            ? L10n("Not added")
                            : L10n("Added privately")
                    )
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(L10n("Bio"))
                            .font(AppTypography.headline)

                        Text(draft.bio)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryForeground)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(L10n("Chicken compatibility"))
                            .font(AppTypography.headline)

                        Text(chickenSummary)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryForeground)
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private var displayedGender: String {
        guard let gender = draft.gender else {
            return L10n("Not selected")
        }

        if gender == .selfDescribed {
            return draft.selfDescribedGender
        }

        return gender.title
    }

    private var displayedInterests: String {
        draft.interestedIn
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    private var displayedRelationshipTypes: String {
        draft.relationshipTypes
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    private var displayedProfileInterests: String {
        draft.interests
            .map(\.title)
            .sorted()
            .joined(separator: ", ")
    }

    private var chickenSummary: String {
        let answer = draft.compatibilityAnswer(
            for: .likesChicken
        )

        return L10n("You: \(answer.ownValue)/7. Partner preference: \(answer.desiredMinimum)–\(answer.desiredMaximum), ideally \(answer.desiredIdeal).")
    }

    private func summaryRow(
        title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(AppTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, AppSpacing.small)
    }
}

#Preview {
    var draft = ProfileDraft()
    draft.displayName = "Sam"
    draft.bio = L10n("Curious, kind and always ready to try a new restaurant.")
    draft.gender = .woman
    draft.interestedIn = [.man, .nonBinary]
    draft.relationshipTypes = [.monogamous]
    draft.interests = [.music, .travel, .movies]

    return OnboardingReviewStepView(draft: draft)
}
