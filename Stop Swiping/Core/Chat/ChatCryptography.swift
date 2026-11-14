import CryptoKit
import Foundation

nonisolated enum SecureChatError: LocalizedError {
    case invalidEnvelope, keyChanged, replaceDevice, noPeerDevice, unavailableKey, tooLong
    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: "This message could not be authenticated."
        case .keyChanged: "Your match’s security key changed. Compare the security code before continuing."
        case .replaceDevice: "Another device is registered for this chat. Confirm switching to this iPhone."
        case .noPeerDevice: "Your match needs to open the chat on their phone first."
        case .unavailableKey: "This message belongs to another device. Its private key is unavailable on this iPhone."
        case .tooLong: "Keep your message under 8,000 characters."
        }
    }
}

/// RFC 9180 authenticated HPKE, provided by CryptoKit. Each envelope uses a fresh
/// ephemeral HPKE context, so delivery can be retried or arrive out of order.
nonisolated enum ChatCryptography {
    static let protocolVersion = "hpke-auth-x25519-v1"
    struct Context: Codable, Equatable, Sendable {
        let matchID: UUID
        let messageID: UUID
        let senderID: UUID
        let senderDeviceID: UUID
        let recipientDeviceID: UUID
        var authenticatedData: Data {
            Data(([ChatCryptography.protocolVersion] + [matchID,messageID,senderID,senderDeviceID,recipientDeviceID]
                .map { $0.uuidString.lowercased() }).joined(separator: "|").utf8)
        }
    }
    struct SealedCopy: Codable, Sendable {
        var encapsulatedKey: Data
        var ciphertext: Data
    }
    struct Envelope: Codable, Sendable {
        let version: String
        let context: Context
        var recipient: SealedCopy
        var sender: SealedCopy
    }
    static func seal(_ text: String, context: Context, senderKey: Curve25519.KeyAgreement.PrivateKey,
                     recipientKey: Curve25519.KeyAgreement.PublicKey) throws -> String {
        guard text.utf8.count <= 8000 else { throw SecureChatError.tooLong }
        func copy(to key: Curve25519.KeyAgreement.PublicKey) throws -> SealedCopy {
            var sender = try HPKE.Sender(recipientKey: key, ciphersuite: .Curve25519_SHA256_ChachaPoly,
                                        info: context.authenticatedData, authenticatedBy: senderKey)
            return try SealedCopy(encapsulatedKey: sender.encapsulatedKey,
                                  ciphertext: sender.seal(Data(text.utf8), authenticating: context.authenticatedData))
        }
        let envelope = try Envelope(version: protocolVersion, context: context,
                                    recipient: copy(to: recipientKey), sender: copy(to: senderKey.publicKey))
        return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }
    static func open(_ encoded: String, expected: Context, privateKey: Curve25519.KeyAgreement.PrivateKey,
                     senderKey: Curve25519.KeyAgreement.PublicKey, isSender: Bool) throws -> String {
        guard encoded.utf8.count <= 131072 else { throw SecureChatError.invalidEnvelope }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(encoded.utf8))
        guard envelope.version == protocolVersion, envelope.context == expected else { throw SecureChatError.invalidEnvelope }
        let copy = isSender ? envelope.sender : envelope.recipient
        var receiver = try HPKE.Recipient(privateKey: privateKey, ciphersuite: .Curve25519_SHA256_ChachaPoly,
                                         info: expected.authenticatedData, encapsulatedKey: copy.encapsulatedKey,
                                         authenticatedBy: senderKey)
        let plaintext = try receiver.open(copy.ciphertext, authenticating: expected.authenticatedData)
        guard let result = String(data: plaintext, encoding: .utf8), plaintext.count <= 8000 else { throw SecureChatError.invalidEnvelope }
        return result
    }
    static func fingerprint(_ key: Data) -> String { SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined() }
    static func safetyCode(matchID: UUID, first: Data, second: Data) -> String {
        let keys = [first,second].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = Array(SHA256.hash(data: Data(matchID.uuidString.lowercased().utf8) + keys[0] + keys[1]))
        return stride(from: 0, to: 30, by: 5).map { offset in
            let value = digest[offset..<offset+5].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return String(format: "%05llu", value % 100000)
        }.joined(separator: " ")
    }
}
