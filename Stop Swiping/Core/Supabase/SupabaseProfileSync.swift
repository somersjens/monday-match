import Foundation
import CryptoKit
import Supabase

@MainActor
protocol ProfileCloudSyncing {
    /// Backs the profile up to the person's own iCloud when it changed, and
    /// sends it to the server only while it takes part in automatic matching.
    /// Switching matching off removes it from the server again
    /// (202611200002_matching_only_profiles.sql).
    func synchronize() async throws
    /// Profiles the server accepted from this object so far. A change means
    /// the server may have searched for a partner just now.
    var completedUploads: Int { get }
    /// The server holds this phone's profile because it takes part in
    /// automatic matching (or has an active match).
    var hasMatchingProfileOnServer: Bool { get }
}

/// Tells the server that this phone's own scan matched the uploaded
/// matching photo (see `PhotoVerificationService`).
@MainActor
protocol DevicePhotoReporting {
    func reportPhotoScan(photoID: UUID) async throws
}

/// The profile as the server keeps it while it takes part in automatic
/// matching. Photos live in private Storage, not as base64 data in the
/// profile JSON. Exact location coordinates stay on the device.
struct SupabaseProfileBackup: Codable, Equatable {
    struct Photo: Codable, Equatable {
        let id: UUID
        let order: Int
    }

    var state: ProfileCreationState
    var draft: ProfileDraft
    let photos: [Photo]

    init(state: ProfileCreationState, draft: ProfileDraft) {
        self.state = state
        self.draft = draft
        photos = draft.photos.sorted { $0.order < $1.order }.map { Photo(id: $0.id, order: $0.order) }
        self.draft.photos = []
        if var location = state.location {
            location.latitude = (location.latitude * 100).rounded() / 100
            location.longitude = (location.longitude * 100).rounded() / 100
            self.state.location = location
        }
        if var location = draft.matchLocation {
            location.latitude = location.coarseLatitude
            location.longitude = location.coarseLongitude
            self.draft.matchLocation = location
        }
    }

    /// The backup apart from the questionnaire step last left open, which
    /// changes while someone browses their profile and matters to no one else.
    var withoutNavigation: Self {
        var copy = self
        copy.state.currentStep = .dateOfBirth
        return copy
    }
}

@MainActor
final class SupabaseProfileSync: ProfileCloudSyncing {
    private let client: SupabaseClient
    private let uploader: SupabaseProfilePhotoUploader
    private let repository: ProfileRepository
    private let store: ProfileCreationStateStoring
    private let defaults: UserDefaults
    private let ownerKey: String
    private let now: () -> Date
    private let uploadsKey: String
    /// The person's own iCloud: the profile's backup, with or without matching.
    private let backup: ProfileICloudBackup?
    private let photoReporter: DevicePhotoReporting?
    private var worker: Task<Void, Error>?
    /// The account this phone was last registered for with the server.
    private var registeredDeviceFor: String?
    private var needsSync = false
    /// Set while a profile is being deleted, so no upload can bring it back.
    private var isDeleting = false
    private(set) var completedUploads = 0

    struct Row: Codable, Equatable {
        let id: String
        let profile: CloudProfile
        let backup: SupabaseProfileBackup

        /// Equal apart from when each was made and the questionnaire step
        /// last left open.
        func hasSameContent(as other: Row) -> Bool {
            var profile = profile
            profile.updatedAt = other.profile.updatedAt
            return id == other.id && profile == other.profile
                && backup.withoutNavigation == other.backup.withoutNavigation
        }
    }

    /// What the server last accepted from this phone for an account, kept
    /// across launches so an unchanged profile is never sent again. Present
    /// only while the server holds a matching profile from this phone.
    struct Upload: Codable {
        var row: Row
        var photoHashes: [UUID: Data]
        /// When the server last accepted or returned this. Missing in
        /// copies saved before the field existed: those count as expired.
        var confirmedAt: Date?
        /// The matching photo whose scan on this phone the server recorded
        /// for the version it stores now.
        var reportedPhotoID: UUID?
    }

    /// The account's saved profile: in the person's own iCloud, or on the
    /// server while it takes part in matching.
    enum SavedProfile {
        case iCloud(ProfileBackupCopy)
        case server(Row)

        var state: ProfileCreationState {
            switch self {
            case .iCloud(let copy): copy.state
            case .server(let row): row.backup.state
            }
        }

        /// Comparable whatever its source: the form the server would keep.
        var comparable: SupabaseProfileBackup {
            switch self {
            case .iCloud(let copy): SupabaseProfileBackup(state: copy.state, draft: copy.draft)
            case .server(let row): row.backup
            }
        }
    }

    /// How long what the server last accepted is trusted without asking.
    /// The server removes the photo of a profile outside matching after 30
    /// days without a save, and a whole profile after 12 months without any
    /// sign of the app (202611190002_traffic_and_retention.sql); checking
    /// again before that means this phone never relies on something gone.
    /// Saving a matching profile again also tells the server it is in use.
    static let confirmationLifetime: TimeInterval = 28 * 24 * 60 * 60

    init(client: SupabaseClient, projectURL: URL, repository: ProfileRepository,
         store: ProfileCreationStateStoring, defaults: UserDefaults = .standard,
         backup: ProfileICloudBackup? = nil, photoReporter: DevicePhotoReporting? = nil,
         now: @escaping () -> Date = Date.init) {
        self.client = client
        self.backup = backup
        self.photoReporter = photoReporter
        self.now = now
        uploader = SupabaseProfilePhotoUploader(client: client, projectURL: projectURL)
        self.repository = repository
        self.store = store
        self.defaults = defaults
        ownerKey = "supabase.profileOwner.\(projectURL.host ?? "default")"
        uploadsKey = "supabase.profileUploads.\(projectURL.host ?? "default")"
    }

    var hasCompletedProfile: Bool { store.load()?.completedAt != nil }

    /// The account's saved profile while the person chooses between it and
    /// the answers just given on this phone.
    private var profileAwaitingChoice: SavedProfile?

    /// The phone's profile belongs to this account: it was sent to it, came
    /// from it, or was chosen over what the account had.
    func ownsProfile(userID: UUID) -> Bool {
        defaults.string(forKey: ownerKey) == userID.uuidString.lowercased()
    }

    /// Throws `AccountProfileChoiceRequired` when the account already has a
    /// profile that differs from the one just finished on this phone. Someone
    /// signing in for the first time, or returning to an empty phone, never
    /// has to choose.
    func connectAccount() async throws {
        profileAwaitingChoice = nil
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        if defaults.string(forKey: ownerKey) == userID, hasCompletedProfile {
            try await synchronize()
            return
        }
        if let saved = try await savedProfile(userID: userID) {
            if conflictsWithPhone(saved) {
                profileAwaitingChoice = saved
                throw AccountProfileChoiceRequired()
            }
            try await restore(saved, userID: userID)
            // The restored profile is in place; bringing iCloud and the
            // server in line with it is retried on the next sync if it fails.
            try? await synchronize()
        } else {
            // A new account explicitly claims the local profile created before sign-in.
            defaults.set(userID, forKey: ownerKey)
            // Into the person's own iCloud; to the server only with matching on.
            try await synchronize()
        }
    }

    /// The new answers win: the account's saved profile is replaced. Its
    /// matches stay the account's, and those made before now keep showing
    /// the profile they were made with.
    func keepNewAnswers() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard let saved = profileAwaitingChoice else { throw SupabaseSetupError.wrongAccount }
        LiveMatchCenter.rememberEarlierProfile(saved.state, replacedAt: now(), defaults: defaults)
        // What the server holds now, unconfirmed: the new answers replace it
        // when they take part in matching, and remove it when they don't.
        let held: Row?
        switch saved {
        case .server(let row): held = row
        case .iCloud: held = try? await load(userID: userID)
        }
        if let held, held.id == userID {
            uploads[userID] = Upload(row: held, photoHashes: [:], confirmedAt: nil)
        }
        defaults.set(userID, forKey: ownerKey)
        profileAwaitingChoice = nil
        // A failed save is retried by signing in again, which now finds this
        // phone owning the account and sends the profile without asking.
        try await synchronize()
    }

    /// The account's saved profile wins over the answers on this phone.
    func restoreAccountProfile() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard let saved = profileAwaitingChoice else { throw SupabaseSetupError.wrongAccount }
        try await restore(saved, userID: userID)
        profileAwaitingChoice = nil
        try? await synchronize()
    }

    /// False when the phone holds a finished profile this account never
    /// chose, because signing in stopped before the person decided. Nothing
    /// is restored over it then.
    func restoreIfNeeded() async throws -> Bool {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        if defaults.string(forKey: ownerKey) == userID, hasCompletedProfile { return true }
        guard let saved = try await savedProfile(userID: userID) else { return true }
        if conflictsWithPhone(saved) { return false }
        try await restore(saved, userID: userID)
        return true
    }

    /// The person's own iCloud first: it holds the profile with or without
    /// matching. The server only has a profile that takes part in matching.
    private func savedProfile(userID: String) async throws -> SavedProfile? {
        if let backup, let copy = try await backup.load(accountID: userID) { return .iCloud(copy) }
        return try await load(userID: userID).map(SavedProfile.server)
    }

    /// The phone holds a finished profile, one the server would accept, that
    /// differs from the account's saved one.
    private func conflictsWithPhone(_ saved: SavedProfile) -> Bool {
        guard let state = store.load(), state.completedAt != nil,
              state.hasAcceptedProfilePrivacy, !state.isUnderageLocked,
              let draft = try? repository.loadProfile() else { return false }
        let local = Self.roundTripped(SupabaseProfileBackup(state: state, draft: draft))
        return local.withoutNavigation != Self.roundTripped(saved.comparable).withoutNavigation
    }

    var hasMatchingProfileOnServer: Bool {
        guard let owner = defaults.string(forKey: ownerKey) else { return false }
        return uploads[owner] != nil
    }

    func synchronize() async throws {
        needsSync = true
        if let worker { try await worker.value; return }
        let task = Task {
            while needsSync {
                needsSync = false
                try await synchronizeCurrentProfile()
            }
        }
        worker = task
        defer { worker = nil }
        try await task.value
    }

    private func synchronizeCurrentProfile() async throws {
        guard !isDeleting, let state = store.load(), state.completedAt != nil,
              state.hasAcceptedProfilePrivacy, !state.isUnderageLocked,
              let draft = try repository.loadProfile() else { return }
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard defaults.string(forKey: ownerKey) == userID else { throw SupabaseSetupError.wrongAccount }
        var failure: Error?
        do {
            if state.autoMatching.isEnabled {
                try await uploadMatchingProfile(state: state, draft: draft, userID: userID)
            } else if uploads[userID] != nil {
                try await leaveMatching(userID: userID)
            }
        } catch {
            failure = error
        }
        do {
            try await backup?.save(state: state, draft: draft, accountID: userID)
        } catch {
            failure = failure ?? error
        }
        if let failure { throw failure }
    }

    /// Automatic matching went off: the server removes the profile, and this
    /// phone its photos. During an active match the server keeps both until
    /// the match ends, then removes them itself.
    private func leaveMatching(userID: String) async throws {
        let left: Bool = try await client.rpc("leave_matching").execute().value
        guard left else { return }
        uploads[userID] = nil
        // Whatever is left is removed by the server's daily job a day later.
        try? await uploader.removePhotos(otherThan: [], userID: userID, minimumAge: 0)
    }

    private func uploadMatchingProfile(state: ProfileCreationState, draft: ProfileDraft, userID: String) async throws {
        let previous = uploads[userID]
        let row = Self.row(userID: userID, state: state, draft: draft, uploader: uploader)
        let photoHashes = Self.photoHashes(draft.photos)
        let isConfirmed = previous?.confirmedAt.map { now().timeIntervalSince($0) < Self.confirmationLifetime } ?? false
        if isConfirmed, let previous, previous.photoHashes == photoHashes,
           previous.row.hasSameContent(as: Self.roundTripped(row)) {
            await registerDevice(userID: userID)
            await reportPhotoScanIfNeeded(state: state, userID: userID)
            return
        }
        var changedPhotos = draft.photos.filter { previous?.photoHashes[$0.id] != photoHashes[$0.id] }
        if previous != nil, !isConfirmed {
            // The server may have removed a photo it no longer needed: send
            // whatever it lacks. Without a listing, every photo is offered
            // and an existing one is kept (uploadPhotos compares its bytes).
            let stored = try? await uploader.storedPhotoIDs(userID: userID)
            let changedIDs = Set(changedPhotos.map(\.id))
            changedPhotos += draft.photos.filter { !changedIDs.contains($0.id) && stored?.contains($0.id) != true }
        }
        let currentIDs = Set(draft.photos.map(\.id))
        let previousIDs = Set(previous?.row.backup.photos.map(\.id) ?? [])
        if !changedPhotos.isEmpty {
            // Make room first: the server keeps at most twelve photos per
            // account. The photos the server's row still names stay until
            // the new row replaces it. Cleanup never blocks a save.
            try? await uploader.removePhotos(otherThan: currentIDs.union(previousIDs), userID: userID)
        }
        _ = try await uploader.uploadPhotos(changedPhotos, userID: userID)
        // Before the profile can be matched: the server keeps a banned
        // person's new account on the same phone out of matching.
        await registerDevice(userID: userID)
        try await client.from("profiles").upsert(row, onConflict: "id").execute()
        // A newly stored matching photo is a new version: its scan is reported again.
        let reported = changedPhotos.contains { $0.id == state.autoMatching.photoID } ? nil : previous?.reportedPhotoID
        uploads[userID] = Upload(row: row, photoHashes: photoHashes, confirmedAt: now(), reportedPhotoID: reported)
        completedUploads += 1
        // A replaced photo is no longer named anywhere on the server.
        try? await uploader.removePhotos(previousIDs.subtracting(currentIDs), userID: userID)
        await reportPhotoScanIfNeeded(state: state, userID: userID)
    }

    /// Tells the server which phone this is, once per account per launch.
    /// A failure never blocks the upload; it is tried on the next one.
    private func registerDevice(userID: String) async {
        guard registeredDeviceFor != userID, let installID = DeviceInstallID.current() else { return }
        struct Params: Encodable { let p_install_id: UUID }
        guard let banned: Bool = try? await client.rpc("register_device", params: Params(p_install_id: installID))
            .execute().value else { return }
        registeredDeviceFor = userID
        if banned { NotificationCenter.default.post(name: .moderationChanged, object: nil) }
    }

    /// The matching photo was verified by a live scan on this phone (setup
    /// can't be completed with a photo otherwise). The phone remembers that,
    /// so switching matching back on needs no new scan: the server is told
    /// again for the version it now stores. A failure is tried on the next sync.
    private func reportPhotoScanIfNeeded(state: ProfileCreationState, userID: String) async {
        guard let photoID = state.autoMatching.photoID, state.autoMatching.hasCompletedSetup,
              let photoReporter, var upload = uploads[userID], upload.reportedPhotoID != photoID else { return }
        do {
            try await photoReporter.reportPhotoScan(photoID: photoID)
            upload.reportedPhotoID = photoID
            uploads[userID] = upload
        } catch {
            // Tried again on the next sync.
        }
    }

    private static func row(userID: String, state: ProfileCreationState, draft: ProfileDraft,
                            uploader: SupabaseProfilePhotoUploader) -> Row {
        let backup = SupabaseProfileBackup(state: state, draft: draft)
        let urls = draft.photos.sorted { $0.order < $1.order }.map {
            uploader.reference(userID: userID, photoID: $0.id)
        }
        return Row(id: userID, profile: CloudProfile(draft: backup.draft, photoURLs: urls), backup: backup)
    }

    /// The row as it comes back from storage. Some answers are not stored
    /// field for field, so a fresh row is compared in this form.
    private static func roundTripped<Value: Codable>(_ value: Value) -> Value {
        (try? JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))) ?? value
    }

    private static func photoHashes(_ photos: [ProfilePhoto]) -> [UUID: Data] {
        Dictionary(photos.map { ($0.id, Data(SHA256.hash(data: $0.imageData))) }, uniquingKeysWith: { first, _ in first })
    }

    private var uploads: [String: Upload] {
        get {
            defaults.data(forKey: uploadsKey)
                .flatMap { try? JSONDecoder().decode([String: Upload].self, from: $0) } ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: uploadsKey) }
        }
    }

    /// Stops uploads and waits for one already running to finish.
    func beginDeletion() async {
        isDeleting = true
        needsSync = false
        _ = try? await worker?.value
    }

    /// Uploads may resume. After a deleted account the phone belongs to no
    /// account until the next sign-in claims it.
    func endDeletion(accountDeleted: Bool) {
        isDeleting = false
        guard accountDeleted else { return }
        defaults.removeObject(forKey: uploadsKey)
        defaults.removeObject(forKey: ownerKey)
    }

    /// The signed-in account, for removing its iCloud backup with it.
    var accountID: String? {
        get async { (try? await client.auth.session)?.user.id.uuidString.lowercased() }
    }

    /// Apple's tokens must be revoked when such an account is deleted.
    var usesSignInWithApple: Bool {
        get async {
            (try? await client.auth.session)?.user.identities?.contains { $0.provider == "apple" } == true
        }
    }

    /// Removes the signed-in account and everything stored for it. Without a
    /// session there is nothing on the server to remove.
    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        guard let session = try? await client.auth.session else { return }
        let userID = session.user.id.uuidString.lowercased()
        if let appleAuthorizationCode {
            // A failed revocation must not keep someone from deleting their
            // account; the account itself, and every token it issued, goes below.
            try? await client.functions.invoke("apple-revoke", options: FunctionInvokeOptions(
                body: ["authorizationCode": appleAuthorizationCode]))
        }
        let bucket = client.storage.from(SupabaseProfilePhotoUploader.bucket)
        // Storage refuses SQL deletes, so photos go first, through its API.
        let files = try await bucket.list(path: userID, options: SearchOptions(limit: 1000))
        let paths = files.map { "\(userID)/\($0.name)" }
        if !paths.isEmpty { _ = try await bucket.remove(paths: paths) }
        try await client.rpc("delete_account").execute()
    }

    private func load(userID: String) async throws -> Row? {
        let rows: [Row] = try await client.from("profiles").select()
            .eq("id", value: userID).not("backup", operator: .is, value: "null").limit(1).execute().value
        return rows.first
    }

    private func restore(_ saved: SavedProfile, userID: String) async throws {
        switch saved {
        case .iCloud(let copy):
            try repository.saveProfile(copy.draft)
            store.save(copy.state)
            defaults.set(userID, forKey: ownerKey)
            backup?.markCurrent(copy, accountID: userID)
            // What the server holds is unknown: a matching profile is sent
            // in full on the next sync (identical photos are kept as they are).
            uploads[userID] = nil
        case .server(let row):
            var draft = row.backup.draft
            for photo in row.backup.photos {
                draft.photos.append(try await uploader.downloadPhoto(id: photo.id, order: photo.order, userID: row.id))
            }
            // Commit only after every photo has downloaded successfully.
            try repository.saveProfile(draft)
            store.save(row.backup.state)
            defaults.set(row.id, forKey: ownerKey)
            // The phone now holds what the server has: nothing to send back.
            uploads[row.id] = Upload(row: Self.row(userID: row.id, state: row.backup.state, draft: draft, uploader: uploader),
                                     photoHashes: Self.photoHashes(draft.photos), confirmedAt: now())
        }
    }
}
