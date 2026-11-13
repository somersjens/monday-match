import UIKit
import Foundation

enum ImageProcessingError: LocalizedError {
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

struct ImageProcessingService {
    let maximumDimension: CGFloat
    let compressionQuality: CGFloat

    init(
        maximumDimension: CGFloat = 1600,
        compressionQuality: CGFloat = 0.82
    ) {
        self.maximumDimension = maximumDimension
        self.compressionQuality = compressionQuality
    }

    func process(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageProcessingError.invalidImageData
        }

        let resizedImage = resizeIfNeeded(image)

        guard let compressedData = resizedImage.jpegData(
            compressionQuality: compressionQuality
        ) else {
            throw ImageProcessingError.failedToCompress
        }

        return compressedData
    }

    private func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        let largestDimension = max(originalSize.width, originalSize.height)

        guard largestDimension > maximumDimension else {
            return image
        }

        let scale = maximumDimension / largestDimension
        let targetSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
