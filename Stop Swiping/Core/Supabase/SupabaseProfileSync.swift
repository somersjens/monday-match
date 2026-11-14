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
        guard let state = store.load(), state.completedAt != nil,
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
