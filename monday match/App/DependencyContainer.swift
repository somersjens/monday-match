import Foundation

struct DependencyContainer {
    let authService: AuthServicing
    let profileRepository: ProfileRepository
    /// Answers from the pre-sign-in profile creation flow, including the
    /// device's underage lock.
    var profileCreationStore: ProfileCreationStateStoring = UserDefaultsProfileCreationStore()

    static var live: DependencyContainer {
        FirebaseBootstrap.configureIfAvailable()

        // The file repository can only fail when the documents directory is
        // unavailable. An in-memory repository then keeps the app usable for the
        // current session instead of silently falling back to mock data.
        let repository: ProfileRepository
        do {
            repository = try FileProfileRepository()
        } catch {
            repository = InMemoryProfileRepository()
        }

        #if canImport(FirebaseAuth)
        return DependencyContainer(
            authService: FirebaseAppleAuthService(),
            profileRepository: repository
        )
        #else
        return DependencyContainer(
            authService: MockAuthService(),
            profileRepository: repository
        )
        #endif
    }
}
