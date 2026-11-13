import Foundation

#if canImport(FirebaseStorage)
import FirebaseStorage

struct FirebaseProfilePhotoUploader: ProfilePhotoUploading {
    private let storage: Storage

    init(storage: Storage = Storage.storage()) {
        self.storage = storage
    }

    func uploadPhotos(
        _ photos: [ProfilePhoto],
        userID: String
    ) async throws -> [URL] {
        var uploadedURLs: [URL] = []

        for photo in photos.sorted(by: { $0.order < $1.order }) {
            let path = "users/\(userID)/profilePhotos/\(photo.id.uuidString).jpg"
            let reference = storage.reference().child(path)

            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            metadata.customMetadata = [
                "order": String(photo.order)
            ]

            _ = try await upload(
                data: photo.imageData,
                metadata: metadata,
                to: reference
            )

            let downloadURL = try await downloadURL(
                from: reference
            )
            uploadedURLs.append(downloadURL)
        }

        return uploadedURLs
    }

    private func upload(
        data: Data,
        metadata: StorageMetadata,
        to reference: StorageReference
    ) async throws -> StorageMetadata {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<StorageMetadata, Error>) in

            reference.putData(
                data,
                metadata: metadata
            ) { metadata, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let metadata else {
                    continuation.resume(
                        throwing: FirebaseStorageUploadError.missingMetadata
                    )
                    return
                }

                continuation.resume(returning: metadata)
            }
        }
    }

    private func downloadURL(
        from reference: StorageReference
    ) async throws -> URL {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in

            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(
                        throwing: FirebaseStorageUploadError.missingDownloadURL
                    )
                    return
                }

                continuation.resume(returning: url)
            }
        }
    }
}

enum FirebaseStorageUploadError: LocalizedError {
    case missingMetadata
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return L10n("Firebase Storage did not return upload metadata.")
        case .missingDownloadURL:
            return L10n("Firebase Storage did not return a download URL.")
        }
    }
}
#endif
