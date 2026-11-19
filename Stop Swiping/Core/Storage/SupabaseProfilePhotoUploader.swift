import CryptoKit
import Foundation
import Supabase

struct SupabaseProfilePhotoUploader: ProfilePhotoUploading {
    static let bucket = "profile-photos"
    let client: SupabaseClient
    let projectURL: URL

    static func path(userID: String, photoID: UUID) -> String {
        "\(userID.lowercased())/\(photoID.uuidString.lowercased()).jpg"
    }

    func reference(userID: String, photoID: UUID) -> URL {
        let path = Self.path(userID: userID, photoID: photoID)
        return projectURL.appending(path: "storage/v1/object/authenticated/\(Self.bucket)/\(path)")
    }

    func uploadPhotos(_ photos: [ProfilePhoto], userID: String) async throws -> [URL] {
        var references: [URL] = []
        for photo in photos.sorted(by: { $0.order < $1.order }) {
            let path = Self.path(userID: userID, photoID: photo.id)
            do {
                try await client.storage.from(Self.bucket).upload(path, data: photo.imageData,
                    options: FileOptions(contentType: "image/jpeg", upsert: false))
            } catch let error as StorageError where error.statusCode == "409" || error.error == "Duplicate" || error.error == "ResourceAlreadyExists" {
                // Reopening the app must not overwrite identical bytes and revoke
                // the trusted Storage-version attestation. Photo IDs are immutable.
                let existing=try await client.storage.from(Self.bucket).download(path:path)
                guard SHA256.hash(data:existing) == SHA256.hash(data:photo.imageData) else {
                    throw PhotoUploadError.changedIdentity
                }
            }
            // Stable, authenticated references; the bucket is never public.
            references.append(reference(userID: userID, photoID: photo.id))
        }
        return references
    }

    /// Removes photos this account no longer uses. The server allows twelve
    /// photos per account (202611190001_abuse_limits.sql).
    func removePhotos(_ ids: Set<UUID>, userID: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await client.storage.from(Self.bucket).remove(paths: ids.map { Self.path(userID: userID, photoID: $0) })
    }

    /// Removes every stored photo outside `kept`, such as photos replaced
    /// before the app removed them itself. Photos younger than `minimumAge`
    /// stay, in case another device of this account is still saving them.
    func removePhotos(otherThan kept: Set<UUID>, userID: String, minimumAge: TimeInterval = 600) async throws {
        let files = try await client.storage.from(Self.bucket).list(path: userID.lowercased(),
                                                                   options: SearchOptions(limit: 1000))
        let cutoff = Date().addingTimeInterval(-minimumAge)
        let stale = files.filter { file in
            guard file.id != nil, let created = file.createdAt, created < cutoff else { return false }
            let id = UUID(uuidString: String(file.name.dropLast(file.name.hasSuffix(".jpg") ? 4 : 0)))
            return id.map { !kept.contains($0) } ?? true
        }
        guard !stale.isEmpty else { return }
        _ = try await client.storage.from(Self.bucket).remove(paths: stale.map { "\(userID.lowercased())/\($0.name)" })
    }

    /// The photo IDs this account has in Storage right now.
    func storedPhotoIDs(userID: String) async throws -> Set<UUID> {
        let files = try await client.storage.from(Self.bucket).list(path: userID.lowercased(),
                                                                   options: SearchOptions(limit: 1000))
        return Set(files.compactMap { file in
            file.id == nil ? nil : UUID(uuidString: String(file.name.dropLast(file.name.hasSuffix(".jpg") ? 4 : 0)))
        })
    }

    enum PhotoUploadError: LocalizedError {
        case changedIdentity
        var errorDescription: String? { L10n("This photo changed on another device. Select it again to upload a new photo.") }
    }
    func downloadPhoto(id: UUID, order: Int, userID: String) async throws -> ProfilePhoto {
        let data = try await client.storage.from(Self.bucket)
            .download(path: Self.path(userID: userID, photoID: id))
        return ProfilePhoto(id: id, imageData: data, order: order)
    }
}
