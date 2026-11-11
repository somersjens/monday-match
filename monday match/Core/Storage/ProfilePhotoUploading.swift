import Foundation

protocol ProfilePhotoUploading {
    func uploadPhotos(
        _ photos: [ProfilePhoto],
        userID: String
    ) async throws -> [URL]
}
