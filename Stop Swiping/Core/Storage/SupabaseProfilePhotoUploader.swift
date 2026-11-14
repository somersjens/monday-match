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

    enum PhotoUploadError: LocalizedError {
        case changedIdentity
        var errorDescription: String? { "This photo changed on another device. Select it again to upload a new photo." }
    }
    func downloadPhoto(id: UUID, order: Int, userID: String) async throws -> ProfilePhoto {
        let data = try await client.storage.from(Self.bucket)
            .download(path: Self.path(userID: userID, photoID: id))
        return ProfilePhoto(id: id, imageData: data, order: order)
    }
}
