import UIKit
import ImageIO
import Foundation

nonisolated enum ImageProcessingError: LocalizedError {
    case invalidImageData
    case failedToResize
    case failedToCompress

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return L10n("The selected image could not be opened.")
        case .failedToResize:
            return L10n("The image could not be resized.")
        case .failedToCompress:
            return L10n("The image could not be compressed.")
        }
    }
}

/// Downsample during decoding, before a full camera image occupies memory.
/// Dimensions are pixels, independent of the device's 2× or 3× display scale.
nonisolated struct ImageProcessingService: Sendable {
    let maximumDimension: CGFloat
    let compressionQuality: CGFloat

    init(
        maximumDimension: CGFloat = 1600,
        compressionQuality: CGFloat = 0.82
    ) {
        self.maximumDimension = maximumDimension
        self.compressionQuality = compressionQuality
    }

    func processInBackground(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try process(data)
        }.value
    }

    func process(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageProcessingError.invalidImageData
        }

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumDimension)),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else {
            throw ImageProcessingError.failedToResize
        }

        guard let compressed = UIImage(cgImage: thumbnail).jpegData(compressionQuality: compressionQuality) else {
            throw ImageProcessingError.failedToCompress
        }
        return compressed
    }
}
