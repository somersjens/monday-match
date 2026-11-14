import CryptoKit
import Foundation
import Security

nonisolated struct ChatPendingMessage: Codable, Sendable {
    let id: UUID
    let senderDeviceID: UUID
    let recipientDeviceID: UUID
    let ciphertext: String
    let createdAt: Date
}

/// Scoped to project/account/conversation; never synced through iCloud or backups.
/// Only encrypted outgoing envelopes persist. Decrypted messages stay in memory.
nonisolated final class ChatKeyStore {
    struct State: Codable {
        var deviceID: UUID
        var privateKey: Data
        var archivedPrivateKeys: [String: Data] = [:]
        var peerPins: [String: Data] = [:]
        var currentPeerDevice: UUID?
        var verifiedPeerDevice: UUID?
        var pending: [ChatPendingMessage] = []
    }
    private let account: String
    private let service = "com.stopswiping.secure-chat.v1"
    init(scope: String) { account = scope }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func load() throws -> State {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound {
            let state = State(deviceID: UUID(), privateKey: Curve25519.KeyAgreement.PrivateKey().rawRepresentation)
            try save(state)
            return state
        }
        guard status == errSecSuccess, let data = value as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(State.self, from: data)
    }
    func save(_ state: State) throws {
        let data = try JSONEncoder().encode(state)
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(values) { _,new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }
    func remove() throws {
        let status=SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status:status) }
    }
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "The iPhone’s secure key storage is unavailable (\(status))." }
    }
}
