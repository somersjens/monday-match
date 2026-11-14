import Foundation

struct DependencyContainer {
    let authService: AuthServicing
    let profileRepository: ProfileRepository
    /// Answers from the pre-sign-in profile creation flow, including the
    /// device's underage lock.
    var profileCreationStore: ProfileCreationStateStoring = UserDefaultsProfileCreationStore()
    var profileSync: ProfileCloudSyncing?
    var chatRepository: SecureChatRepository?
    var photoVerification: AWSPhotoVerificationService?

    static var live: DependencyContainer {
        // The file repository can only fail when the documents directory is
        // unavailable. An in-memory repository then keeps the app usable for the
        // current session instead of silently falling back to mock data.
        let repository: ProfileRepository
        do {
            repository = try FileProfileRepository()
        } catch {
            repository = InMemoryProfileRepository()
        }

        let store = UserDefaultsProfileCreationStore()
        guard let configuration = SupabaseConfiguration.bundled else {
            return DependencyContainer(authService: UnconfiguredSupabaseAuthService(), profileRepository: repository,
                                       profileCreationStore: store)
        }
        let client = configuration.makeClient()
        let sync = SupabaseProfileSync(client: client, projectURL: configuration.url, repository: repository, store: store)
        return DependencyContainer(authService: SupabaseAuthService(client: client, profileSync: sync),
                                   profileRepository: repository, profileCreationStore: store, profileSync: sync,
                                   chatRepository: SupabaseChatRepository(client: client, projectURL: configuration.url),
                                   photoVerification: AWSPhotoVerificationService(client: client, profileSync: sync))
    }
}
