import Foundation

/// Deletes the profile everywhere: first the account on the server, with
/// its auto matching entry, photos, matches and chats; then everything this
/// app stored on the phone. Nothing local is removed if the server step fails.
///
/// App Store purchases and the early access claim belong to the Apple ID, so
/// they stay. So does the app language, a setting of the phone, not the profile.
@MainActor
struct ProfileDeletionService {
    let profileRepository: ProfileRepository
    let profileCreationStore: ProfileCreationStateStoring
    let server: SupabaseProfileSync?
    let authService: AuthServicing
    var defaults: UserDefaults = .standard

    /// True when deleting first needs Apple to confirm the Apple ID again.
    var needsAppleAuthorization: Bool {
        get async { await server?.usesSignInWithApple == true }
    }

    func deleteProfile(appleAuthorizationCode: String? = nil) async throws {
        await server?.beginDeletion()
        do {
            try await server?.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        } catch {
            server?.endDeletion(accountDeleted: false)
            throw error
        }
        try? await authService.signOut()
        try wipeLocalData()
        server?.endDeletion(accountDeleted: true)
    }

    private func wipeLocalData() throws {
        profileCreationStore.clear()
        SavedMatchStore.clear(defaults: defaults)
        try ChatKeyStore.removeAll()
        try profileRepository.deleteProfile()
    }
}
