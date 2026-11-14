import Foundation
import Security

enum LifetimeProductID: String, CaseIterable {
    case earlyAdopter = "lifetime_access_early_adopter"
    case lifetime = "lifetime_access"
}

/// Dates are absolute instants: a day means 86,400 elapsed seconds, including
/// across daylight-saving changes and travel. StoreKit supplies the original
/// purchase date on restoration, never a fresh seven-day window.
struct EarlyAccessLedger: Codable, Equatable {
    static let day: TimeInterval = 86_400
    var startedAt: Date?
    /// Explicitly reactivated through the hidden hold gesture, in every build.
    var reactivatedAt: Date?
    var originalTransactionID: String?
    var completedAt: Date?
    var requestedAt: Date?
    var reminderEnabled = false

    var effectiveStartedAt: Date? { reactivatedAt ?? startedAt }
    var deadline: Date? { effectiveStartedAt?.addingTimeInterval(7 * Self.day) }
    var reminderDate: Date? { effectiveStartedAt?.addingTimeInterval(6 * Self.day) }

    mutating func register(originalID: String, purchasedAt: Date) {
        // Never move an existing deadline forward, including after a refund.
        let firstStart = min(requestedAt ?? purchasedAt, purchasedAt)
        startedAt = min(startedAt ?? firstStart, firstStart)
        originalTransactionID = originalID
        requestedAt = nil
    }

    func completedInTime(_ date: Date?) -> Bool {
        guard let date, let startedAt = effectiveStartedAt, let deadline else { return false }
        return date >= startedAt && date < deadline
    }

    func permitsAccess(at now: Date, profileCompletedAt: Date?) -> Bool {
        guard let deadline else { return false }
        return now < deadline || completedInTime(completedAt) || completedInTime(profileCompletedAt)
    }

    func canOfferEarlyAccess(at now: Date) -> Bool {
        guard let deadline else { return true }
        return now < deadline || completedInTime(completedAt)
    }
}

protocol EarlyAccessLedgerStoring {
    func load() throws -> EarlyAccessLedger
    func save(_ ledger: EarlyAccessLedger) throws
}

/// Keeps the first claim through local profile resets and app reinstalls.
/// StoreKit's signed transaction history is the account-level source of truth.
struct KeychainEarlyAccessLedgerStore: EarlyAccessLedgerStoring {
    private let service = "Hakketjak.monday-match.early-access.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "first-claim"]
    }

    func load() throws -> EarlyAccessLedger {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return EarlyAccessLedger() }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LedgerError.keychain(status)
        }
        return try JSONDecoder().decode(EarlyAccessLedger.self, from: data)
    }

    func save(_ ledger: EarlyAccessLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        let changes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw LedgerError.keychain(added) }
        } else if status != errSecSuccess {
            throw LedgerError.keychain(status)
        }
    }

    private enum LedgerError: LocalizedError {
        case keychain(OSStatus)
        var errorDescription: String? { L10n("Your access could not be saved securely. Please try again.") }
    }
}
