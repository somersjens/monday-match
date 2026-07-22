import Foundation

@MainActor
final class SignedInRootViewModel: ObservableObject {
    @Published var selectedTab: SignedInTab = .dashboard
    @Published private(set) var profile: ProfileDraft
    @Published private(set) var matchResult: MatchResult? = .successfulMock
    @Published private(set) var conversation: ChatConversation?
    @Published var storageErrorMessage: String?

    private let repository: ProfileRepository

    init(
        repository: ProfileRepository,
        profile: ProfileDraft = .mockCompleted
    ) {
        self.repository = repository
        self.profile = profile

        if let matchResult,
           case .matched(let matchedProfile) = matchResult.outcome {
            conversation = .mock(
                matchID: matchedProfile.id
            )
        }
    }

    func loadProfile() {
        do {
            if let storedProfile = try repository.loadProfile() {
                profile = storedProfile
            } else {
                try repository.saveProfile(profile)
            }
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }

    func updateProfile(_ updatedProfile: ProfileDraft) {
        profile = updatedProfile

        do {
            try repository.saveProfile(updatedProfile)
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }

    func deleteLocalProfile() {
        do {
            try repository.deleteProfile()
            profile = .mockCompleted
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }

    func clearMatch() {
        matchResult = nil
        conversation = nil
    }
}
