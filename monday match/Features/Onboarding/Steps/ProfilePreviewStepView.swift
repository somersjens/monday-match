import SwiftUI
import UIKit

struct ProfilePreviewStepView: View {
    let draft: ProfileDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    Text("This is how your match sees you.")
                        .font(AppTypography.title)

                    Text(
                        "Review your profile before completing onboarding. You can edit these details later."
                    )
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryForeground)
                    .lineSpacing(4)
                }

                ProfilePreviewCard(draft: draft)

                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.medium) {
                        Text("Private matching details")
                            .font(AppTypography.headline)

                        privateRow(
                            title: "Maximum distance",
                            value: "\(draft.preferredRadiusKilometers) km"
                        )

                        privateRow(
                            title: "Location",
                            value: draft.matchLocation == nil
                                ? "Not added"
                                : "Stored privately"
                        )

                        privateRow(
                            title: "Chicken answer",
                            value: chickenSummary
                        )
                    }
                }
            }
            .padding(AppSpacing.large)
        }
    }

    private var chickenSummary: String {
        let answer = draft.compatibilityAnswer(
            for: .likesChicken
        )

        return "\(answer.ownValue)/7 · prefers \(answer.desiredMinimum)–\(answer.desiredMaximum)"
    }

    private func privateRow(
        title: String,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.medium) {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)

            Spacer()

            Text(value)
                .font(AppTypography.body.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct ProfilePreviewCard: View {
    let draft: ProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainPhoto

            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("\(draft.displayName), \(draft.age())")
                        .font(AppTypography.title)

                    Text(relationshipLine)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryForeground)
                }

                Text(draft.bio)
                    .font(AppTypography.body)
                    .lineSpacing(4)

                if !draft.interests.isEmpty {
                    interestFlow
                }

                if draft.photos.count > 1 {
                    photoThumbnails
                }
            }
            .padding(AppSpacing.large)
        }
        .background(AppColors.secondaryBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
        )
    }

    private var mainPhoto: some View {
        Group {
            if let firstPhoto = draft.photos.sorted(by: { $0.order < $1.order }).first,
               let image = UIImage(data: firstPhoto.imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    AppColors.accent.opacity(0.12)

                    Image(systemName: "person.crop.square")
                        .font(.system(size: 72))
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .frame(height: 360)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var relationshipLine: String {
        draft.relationshipTypes
            .map(\.title)
            .sorted()
            .joined(separator: " · ")
    }

    private var interestFlow: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 96), spacing: AppSpacing.small)
            ],
            alignment: .leading,
            spacing: AppSpacing.small
        ) {
            ForEach(
                draft.interests.sorted(by: { $0.title < $1.title })
            ) { interest in
                Label(
                    interest.title,
                    systemImage: interest.symbol
                )
                .font(AppTypography.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppColors.background)
                .clipShape(Capsule())
            }
        }
    }

    private var photoThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                ForEach(
                    draft.photos
                        .sorted(by: { $0.order < $1.order })
                        .dropFirst()
                ) { photo in
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 96)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                            .clipped()
                    }
                }
            }
        }
    }
}

#Preview {
    var draft = ProfileDraft()
    draft.displayName = "Sam"
    draft.bio = "Curious, kind and always ready to try a new restaurant."
    draft.gender = .woman
    draft.interestedIn = [.man]
    draft.relationshipTypes = [.monogamous]
    draft.interests = [.music, .travel, .movies]

    return ProfilePreviewStepView(draft: draft)
}
