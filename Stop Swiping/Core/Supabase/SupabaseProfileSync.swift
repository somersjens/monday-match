import Foundation
import CryptoKit
import Supabase

@MainActor
protocol ProfileCloudSyncing {
    /// Sends the profile when it differs from the server's copy.
    func synchronize() async throws
    /// The automatic sync after an edit or on returning to the app. The
    /// server only needs a profile that takes part in automatic matching, or
    /// one that just stopped; otherwise the profile stays on the phone and the
    /// account keeps the copy it last received.
    func synchronizeMatchingProfile() async throws
    /// Profiles the server accepted from this object so far. A change means
    /// the server may have searched for a partner just now.
    var completedUploads: Int { get }
}

/// Photos live in private Storage, not as base64 data in the profile JSON.
/// Exact location coordinates stay on the device.
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
    private var worker: Task<Void, Error>?
    private var needsSync = false
    /// Set when a pending sync must send the profile even if it takes no
    /// part in matching (signing in, verifying a photo).
    private var needsUploadOutsideMatching = false
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
    /// across launches so an unchanged profile is never sent again.
    struct Upload: Codable {
        var row: Row
        var photoHashes: [UUID: Data]
        /// When the server last accepted or returned this. Missing in
        /// copies saved before the field existed: those count as expired.
        var confirmedAt: Date?
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
         now: @escaping () -> Date = Date.init) {
        self.client = client
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
    private var profileAwaitingChoice: Row?

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
        } else if let row = try await load(userID: userID) {
            if conflictsWithPhone(row) {
                profileAwaitingChoice = row
                throw AccountProfileChoiceRequired()
            }
            try await restore(row)
        } else {
            // A new account explicitly claims the local profile created before sign-in.
            defaults.set(userID, forKey: ownerKey)
            try await synchronize()
        }
    }

    /// The new answers win: the account's saved profile is replaced. Its
    /// matches stay the account's, and those made before now keep showing
    /// the profile they were made with.
    func keepNewAnswers() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard let row = profileAwaitingChoice, row.id == userID else { throw SupabaseSetupError.wrongAccount }
        LiveMatchCenter.rememberEarlierProfile(row.backup.state, replacedAt: now(), defaults: defaults)
        // What the server holds now, unconfirmed: every photo of the new
        // profile is sent, and the old ones stay until the new row replaces
        // the one naming them.
        uploads[userID] = Upload(row: row, photoHashes: [:], confirmedAt: nil)
        defaults.set(userID, forKey: ownerKey)
        profileAwaitingChoice = nil
        // A failed save is retried by signing in again, which now finds this
        // phone owning the account and sends the profile without asking.
        try await synchronize()
    }

    /// The account's saved profile wins over the answers on this phone.
    func restoreAccountProfile() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard let row = profileAwaitingChoice, row.id == userID else { throw SupabaseSetupError.wrongAccount }
        try await restore(row)
        profileAwaitingChoice = nil
    }

    /// False when the phone holds a finished profile this account never
    /// chose, because signing in stopped before the person decided. Nothing
    /// is restored over it then.
    func restoreIfNeeded() async throws -> Bool {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        if defaults.string(forKey: ownerKey) == userID, hasCompletedProfile { return true }
        guard let row = try await load(userID: userID) else { return true }
        if conflictsWithPhone(row) { return false }
        try await restore(row)
        return true
    }

    /// The phone holds a finished profile, one the server would accept, that
    /// differs from the account's saved one.
    private func conflictsWithPhone(_ row: Row) -> Bool {
        guard let state = store.load(), state.completedAt != nil,
              state.hasAcceptedProfilePrivacy, !state.isUnderageLocked,
              let draft = try? repository.loadProfile() else { return false }
        let local = Self.roundTripped(Self.row(userID: row.id, state: state, draft: draft, uploader: uploader))
        return !local.hasSameContent(as: Self.roundTripped(row))
    }

    func synchronize() async throws {
        try await synchronize(outsideMatching: true)
    }

    func synchronizeMatchingProfile() async throws {
        try await synchronize(outsideMatching: false)
    }

    private func synchronize(outsideMatching: Bool) async throws {
        needsSync = true
        if outsideMatching { needsUploadOutsideMatching = true }
        if let worker { try await worker.value; return }
        let task = Task {
            while needsSync {
                needsSync = false
                let outsideMatching = needsUploadOutsideMatching
                needsUploadOutsideMatching = false
                try await uploadCurrentProfile(outsideMatching: outsideMatching)
            }
        }
        worker = task
        defer { worker = nil }
        try await task.value
    }

    private func uploadCurrentProfile(outsideMatching: Bool) async throws {
        guard !isDeleting, let state = store.load(), state.completedAt != nil,
              state.hasAcceptedProfilePrivacy, !state.isUnderageLocked,
              let draft = try repository.loadProfile() else { return }
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard defaults.string(forKey: ownerKey) == userID else { throw SupabaseSetupError.wrongAccount }
        let previous = uploads[userID]
        // Edits to a profile outside matching stay on the phone. Switching
        // matching off is still sent, so the server stops matching it.
        let wasMatching = previous?.row.backup.state.autoMatching.isEnabled == true
        guard outsideMatching || state.autoMatching.isEnabled || wasMatching else { return }
        let row = Self.row(userID: userID, state: state, draft: draft, uploader: uploader)
        let photoHashes = Self.photoHashes(draft.photos)
        let isConfirmed = previous?.confirmedAt.map { now().timeIntervalSince($0) < Self.confirmationLifetime } ?? false
        if isConfirmed, let previous, previous.photoHashes == photoHashes,
           previous.row.hasSameContent(as: Self.roundTripped(row)) { return }
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
        try await client.from("profiles").upsert(row, onConflict: "id").execute()
        uploads[userID] = Upload(row: row, photoHashes: photoHashes, confirmedAt: now())
        completedUploads += 1
        // A replaced photo is no longer named anywhere on the server.
        try? await uploader.removePhotos(previousIDs.subtracting(currentIDs), userID: userID)
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
    private static func roundTripped(_ row: Row) -> Row {
        (try? JSONDecoder().decode(Row.self, from: JSONEncoder().encode(row))) ?? row
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

    private func restore(_ row: Row) async throws {
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
