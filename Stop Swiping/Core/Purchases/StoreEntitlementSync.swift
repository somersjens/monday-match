import Foundation
import Supabase

/// Sends the server proof of lifetime access, so it belongs to the account
/// and not only to this iPhone: another phone, or the Android app later, can
/// then rely on it. The server checks Apple's signature itself
/// (`store-entitlement` edge function); the app never claims access on its own.
@MainActor
protocol StoreEntitlementRecording {
    func record(appStoreTransactions: [String], appStoreRenewals: [String]) async throws
    /// What the signed-in account owns, from every device and store.
    func accountEntitlements() async throws -> [AccountEntitlement]
}

extension StoreEntitlementRecording {
    func accountEntitlements() async throws -> [AccountEntitlement] { [] }
}

/// One purchase the server verified for the signed-in account, from any
/// device or store: what lets a Google account that bought on one phone sign
/// in on another phone, another Apple ID or (later) Android.
struct AccountEntitlement: Codable, Equatable {
    let productID: LifetimeProductID
    let purchasedAt: Date
    /// A subscription's current period end, as the server last heard it.
    let expiresAt: Date?
    let revoked: Bool
    /// Where it was bought: "app_store" or "play". Nil in copies cached
    /// before the field existed.
    var store: String? = nil
    /// Whether a monthly plan will be charged again; nil while unknown.
    var autoRenews: Bool? = nil

    var subscriptionStore: SubscriptionStore? {
        switch store {
        case "app_store": .appStore
        case "play": .googlePlay
        default: nil
        }
    }

    func isActive(at now: Date) -> Bool {
        guard !revoked else { return false }
        guard productID.isSubscription else { return true }
        return expiresAt.map { now < $0 } ?? false
    }
}

@MainActor
final class SupabaseStoreEntitlementRecorder: StoreEntitlementRecording {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func record(appStoreTransactions: [String], appStoreRenewals: [String]) async throws {
        struct Body: Encodable { let appStoreTransactions: [String]; let appStoreRenewals: [String] }
        try await client.functions.invoke("store-entitlement", options: FunctionInvokeOptions(
            body: Body(appStoreTransactions: appStoreTransactions, appStoreRenewals: appStoreRenewals)))
    }

    func accountEntitlements() async throws -> [AccountEntitlement] {
        struct Row: Decodable {
            let store: String
            let product_id: String
            let purchased_at: Date
            let expires_at: Date?
            let revoked: Bool
            let auto_renews: Bool?
        }
        let rows: [Row] = try await client.rpc("my_store_entitlements").execute().value
        // A product this version doesn't know (added later) grants nothing here.
        return rows.compactMap { row in
            LifetimeProductID(rawValue: row.product_id).map {
                AccountEntitlement(productID: $0, purchasedAt: row.purchased_at, expiresAt: row.expires_at,
                                   revoked: row.revoked, store: row.store, autoRenews: row.auto_renews)
            }
        }
    }
}

/// Contacts the server only when there is something new: once after an
/// account first appears, and again after a purchase, restore or refund.
@MainActor
final class StoreEntitlementSync {
    static let recordedKey = "storeEntitlements.recorded.v1"
    private let recorder: StoreEntitlementRecording
    private let purchasing: LifetimePurchasing
    private let defaults: UserDefaults
    private var isSyncing = false

    init(recorder: StoreEntitlementRecording, purchasing: LifetimePurchasing, defaults: UserDefaults = .standard) {
        self.recorder = recorder
        self.purchasing = purchasing
        self.defaults = defaults
    }

    /// What was last accepted, so an unchanged set is never sent twice.
    static func fingerprint(_ transactions: [SignedStoreTransaction]) -> String {
        transactions.map { transaction in
            let period = transaction.expiresAt.map { ":\(Int($0.timeIntervalSince1970))" } ?? ""
            let renews = transaction.willAutoRenew.map { $0 ? ":renews" : ":ends" } ?? ""
            return "\(transaction.originalID):\(transaction.isRevoked ? 1 : 0)\(period)\(renews)"
        }.sorted().joined(separator: ",")
    }

    /// True when the server accepted something new, so what the account
    /// owns is worth reading again.
    @discardableResult
    func syncIfNeeded() async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        let transactions = await purchasing.signedTransactions()
        guard !transactions.isEmpty else { return false }
        let fingerprint = Self.fingerprint(transactions)
        guard defaults.string(forKey: Self.recordedKey) != fingerprint else { return false }
        let sent = Array(transactions.prefix(10))
        do {
            try await recorder.record(appStoreTransactions: sent.map(\.jws),
                                      appStoreRenewals: sent.compactMap(\.renewalJWS))
            defaults.set(fingerprint, forKey: Self.recordedKey)
            return true
        } catch {
            // Tried again at the next launch or purchase.
            return false
        }
    }

    /// Nil when the server can't be reached: the last known answer stays.
    func accountEntitlements() async -> [AccountEntitlement]? {
        try? await recorder.accountEntitlements()
    }

    /// Another account may sign in next; it gets its own record.
    func accountSignedOut() {
        defaults.removeObject(forKey: Self.recordedKey)
    }
}
