import CryptoKit
import Foundation
import Security

enum NonceGeneratorError: LocalizedError {
    case randomGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed(let status):
            return "Secure nonce generation failed with status \(status)."
        }
    }
}

struct NonceGenerator {
    func randomNonce(length: Int = 32) throws -> String {
        precondition(length > 0)

        let characters = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var randomBytes = [UInt8](
            repeating: 0,
            count: length
        )

        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )

        guard status == errSecSuccess else {
            throw NonceGeneratorError.randomGenerationFailed(status)
        }

        return String(
            randomBytes.map {
                characters[Int($0) % characters.count]
            }
        )
    }

    func sha256(_ input: String) -> String {
        let digest = SHA256.hash(
            data: Data(input.utf8)
        )

        return digest.map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
