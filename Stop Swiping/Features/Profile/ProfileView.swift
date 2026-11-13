import SwiftUI

struct ProfileView: View {
    @Binding var profile: ProfileDraft
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    ProfileSummaryCard(profile: profile)

                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.medium) {
                            Text(L10n("Bio"))
                                .font(AppTypography.headline)

                            Text(profile.bio)
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.secondaryForeground)
                                .lineSpacing(4)
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: AppSpacing.medium) {
                            Text(L10n("Interests"))
                                .font(AppTypography.headline)

                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: 100))
                                ],
                                alignment: .leading,
                                spacing: AppSpacing.small
                            ) {
                                ForEach(
                                    profile.interests.sorted(by: { $0.title < $1.title })
                                ) { interest in
                                    Label(
                                        interest.title,
                                        systemImage: interest.symbol
                                    )
                                    .font(AppTypography.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(AppColors.secondaryBackground)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(AppSpacing.large)
            }
            .navigationTitle(L10n("Profile"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n("Edit")) {
                        isEditing = true
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                ProfileEditView(profile: $profile)
            }
        }
    }
}

private struct ProfileSummaryCard: View {
    let profile: ProfileDraft

    var body: some View {
        AppCard {
            HStack(spacing: AppSpacing.medium) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent.opacity(0.12))
                        .frame(width: 84, height: 84)

                    Image(systemName: "person.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppColors.accent)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text("\(profile.displayName), \(profile.age())")
                        .font(AppTypography.title)

                    Text(
                        profile.relationshipTypes
                            .map(\.title)
                            .sorted()
                            .joined(separator: " · ")
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryForeground)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    ProfileView(
        profile: .constant(.mockCompleted)
    )
}
