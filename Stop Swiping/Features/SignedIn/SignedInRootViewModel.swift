import Combine
import Foundation

@MainActor
final class SignedInRootViewModel: ObservableObject {
    @Published var selectedTab: SignedInTab = .dashboard
    @Published private(set) var profile: ProfileDraft
    @Published private(set) var matchResult: MatchResult?
    /// Owned here so it survives navigating in and out of the chat. Sent
    /// messages live in this single instance for as long as the match is active.
    @Published private(set) var chatViewModel: ChatViewModel?
    @Published var storageErrorMessage: String?

    private let repository: ProfileRepository

    init(
        repository: ProfileRepository,
        profile: ProfileDraft? = nil
    ) {
        self.repository = repository
        // Built in the body rather than as a default argument: this initializer
        // is MainActor-isolated, but default arguments run nonisolated and the
        // ProfileDraft initializer is MainActor-isolated too.
        self.profile = profile ?? ProfileDraft()

        if let matchResult,
           case .matched(let matchedProfile) = matchResult.outcome {
            chatViewModel = ChatViewModel(
                conversation: .mock(matchID: matchedProfile.id)
            )
        }
    }

    func loadProfile() {
        do {
            // Only read here. Writing a placeholder profile when the store is
            // empty would overwrite the real profile written by onboarding.
            if let storedProfile = try repository.loadProfile() {
                profile = storedProfile
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
            profile = ProfileDraft()
        } catch {
            storageErrorMessage = error.localizedDescription
        }
    }

    func clearMatch() {
        matchResult = nil
        chatViewModel = nil
    }
}
