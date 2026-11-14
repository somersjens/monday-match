import Foundation
import CryptoKit
import Supabase

@MainActor
protocol ProfileCloudSyncing {
    func synchronize() async throws
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
}

@MainActor
final class SupabaseProfileSync: ProfileCloudSyncing {
    private let client: SupabaseClient
    private let uploader: SupabaseProfilePhotoUploader
    private let repository: ProfileRepository
    private let store: ProfileCreationStateStoring
    private let defaults: UserDefaults
    private let ownerKey: String
    private var worker: Task<Void, Error>?
    private var needsSync = false
    private var uploadedPhotos: [String: [UUID: Data]] = [:]
    /// Set while a profile is being deleted, so no upload can bring it back.
    private var isDeleting = false

    struct Row: Codable {
        let id: String
        let profile: CloudProfile
        let backup: SupabaseProfileBackup
    }

    init(client: SupabaseClient, projectURL: URL, repository: ProfileRepository,
         store: ProfileCreationStateStoring, defaults: UserDefaults = .standard) {
        self.client = client
        uploader = SupabaseProfilePhotoUploader(client: client, projectURL: projectURL)
        self.repository = repository
        self.store = store
        self.defaults = defaults
        ownerKey = "supabase.profileOwner.\(projectURL.host ?? "default")"
    }

    var hasCompletedProfile: Bool { store.load()?.completedAt != nil }

    func connectAccount() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        if defaults.string(forKey: ownerKey) == userID, hasCompletedProfile {
            try await synchronize()
        } else if let row = try await load(userID: userID) {
            try await restore(row)
        } else {
            // A new account explicitly claims the local profile created before sign-in.
            defaults.set(userID, forKey: ownerKey)
            try await synchronize()
        }
    }

    func restoreIfNeeded() async throws {
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        if defaults.string(forKey: ownerKey) == userID, hasCompletedProfile { return }
        if let row = try await load(userID: userID) {
            try await restore(row)
        }
    }

    func synchronize() async throws {
        needsSync = true
        if let worker { try await worker.value; return }
        let task = Task {
            while needsSync {
                needsSync = false
                try await uploadCurrentProfile()
            }
        }
        worker = task
        defer { worker = nil }
        try await task.value
    }

    private func uploadCurrentProfile() async throws {
        guard !isDeleting, let state = store.load(), state.completedAt != nil,
              state.hasAcceptedProfilePrivacy, !state.isUnderageLocked,
              let draft = try repository.loadProfile() else { return }
        let userID = try await client.auth.session.user.id.uuidString.lowercased()
        guard defaults.string(forKey: ownerKey) == userID else { throw SupabaseSetupError.wrongAccount }
        let backup = SupabaseProfileBackup(state: state, draft: draft)
        let changedPhotos = draft.photos.filter { uploadedPhotos[userID]?[$0.id] != Data(SHA256.hash(data: $0.imageData)) }
        _ = try await uploader.uploadPhotos(changedPhotos, userID: userID)
        for photo in changedPhotos { uploadedPhotos[userID, default: [:]][photo.id] = Data(SHA256.hash(data: photo.imageData)) }
        let urls = draft.photos.sorted { $0.order < $1.order }.map {
            uploader.reference(userID: userID, photoID: $0.id)
        }
        let profile = CloudProfile(draft: backup.draft, photoURLs: urls)
        try await client.from("profiles").upsert(Row(id: userID, profile: profile, backup: backup), onConflict: "id")
            .execute()
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
        uploadedPhotos = [:]
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
    }
}
