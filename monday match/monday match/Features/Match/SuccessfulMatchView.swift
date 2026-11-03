import SwiftUI
import UIKit

struct SuccessfulMatchView: View {
    let result: MatchResult
    let profile: MatchedProfile
    let chatViewModel: ChatViewModel?
    let onEndMatch: () -> Void

    @State private var showsEndMatchConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                compatibilityHeader
                matchCard
                conversationCard
                endMatchButton
            }
            .padding(AppSpacing.large)
        }
        .confirmationDialog(
            "End this match?",
            isPresented: $showsEndMatchConfirmation,
            titleVisibility: .visible
        ) {
            Button("End match", role: .destructive) {
                onEndMatch()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The conversation will close and you can opt in again for a future round."
            )
        }
    }

    private var compatibilityHeader: some View {
        VStack(spacing: AppSpacing.small) {
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.accent)

            Text("You matched")
                .font(AppTypography.title)

            if let score = result.compatibilityScore {
                Text("\(score)% compatibility")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var matchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                AppColors.accent.opacity(0.12)

                if let imageData = profile.imageData,
                   let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 88))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: AppSpacing.large) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("\(profile.displayName), \(profile.age)")
                        .font(AppTypography.title)

                    Label(
                        "About \(profile.distanceKilometers) km away",
                        systemImage: "location"
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                Text(profile.bio)
                    .font(AppTypography.body)
                    .lineSpacing(4)

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 100))
                    ],
                    alignment: .leading,
                    spacing: AppSpacing.small
                ) {
                    ForEach(profile.interests) { interest in
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

    private var conversationCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("Start the conversation")
                    .font(AppTypography.headline)

                Text(
                    "Ask \(profile.displayName) about cooking for friends or a favorite coffee place."
                )
                .font(AppTypography.body)
                .foregroundStyle(AppColors.secondaryForeground)

                if let chatViewModel {
                    NavigationLink {
                        ChatView(
                            viewModel: chatViewModel
                        )
                    } label: {
                        Text("Open chat")
                            .font(AppTypography.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 18))
                    .tint(AppColors.accent)
                }
            }
        }
    }

    private var endMatchButton: some View {
        Button(role: .destructive) {
            showsEndMatchConfirmation = true
        } label: {
            Text("End match")
                .font(AppTypography.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.medium)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

#Preview {
    NavigationStack {
        SuccessfulMatchView(
            result: .successfulMock,
            profile: .mock,
            chatViewModel: ChatViewModel(conversation: .mock()),
            onEndMatch: {}
        )
    }
}
