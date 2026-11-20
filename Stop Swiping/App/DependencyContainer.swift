import Foundation

struct DependencyContainer {
    let authService: AuthServicing
    let profileRepository: ProfileRepository
    /// Answers from the pre-sign-in profile creation flow, including the
    /// device's underage lock.
    var profileCreationStore: ProfileCreationStateStoring = UserDefaultsProfileCreationStore()
    var profileSync: ProfileCloudSyncing?
    var chatRepository: SecureChatRepository?
    var photoVerification: PhotoVerificationService?
    /// Registers this phone for pushes about matches and messages.
    var pushRegistration: PushDeviceRegistering?
    /// Records lifetime access against the account, verified by the server.
    var storeEntitlements: StoreEntitlementRecording?
    /// The matches under My matches, backed up to the person's own iCloud.
    var savedMatchBackup: SavedMatchCloudBackup?
    /// The account's profile, backed up to the person's own iCloud.
    var profileBackup: ProfileICloudBackup?

    @MainActor
    var profileDeletion: ProfileDeletionService {
        ProfileDeletionService(profileRepository: profileRepository, profileCreationStore: profileCreationStore,
                               server: profileSync as? SupabaseProfileSync, authService: authService,
                               savedMatchBackup: savedMatchBackup, profileBackup: profileBackup)
    }

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
        // In iCloud, not on our server: it works with or without an account.
        let savedMatchBackup = SavedMatchCloudBackup(store: CloudKitSavedMatchStore())
        // The profile too: an account backs it up here, and the server only
        // receives it while it takes part in automatic matching.
        let profileBackup = ProfileICloudBackup(store: CloudKitProfileBackupStore())
        guard let configuration = SupabaseConfiguration.bundled else {
            return DependencyContainer(authService: UnconfiguredSupabaseAuthService(), profileRepository: repository,
                                       profileCreationStore: store, savedMatchBackup: savedMatchBackup,
                                       profileBackup: profileBackup)
        }
        let client = configuration.makeClient()
        let sync = SupabaseProfileSync(client: client, projectURL: configuration.url, repository: repository, store: store,
                                       backup: profileBackup, photoReporter: DevicePhotoScanReporter(client: client))
        return DependencyContainer(authService: SupabaseAuthService(client: client, profileSync: sync),
                                   profileRepository: repository, profileCreationStore: store, profileSync: sync,
                                   chatRepository: SupabaseChatRepository(client: client, projectURL: configuration.url),
                                   photoVerification: PhotoVerificationService(client: client, profileSync: sync),
                                   pushRegistration: SupabasePushDeviceRegistration(client: client),
                                   storeEntitlements: SupabaseStoreEntitlementRecorder(client: client),
                                   savedMatchBackup: savedMatchBackup, profileBackup: profileBackup)
    }
}
