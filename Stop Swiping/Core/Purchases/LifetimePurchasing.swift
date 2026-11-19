import Foundation
import StoreKit
import UIKit

struct LifetimeStoreProduct: Equatable {
    let id: LifetimeProductID
    let displayPrice: String
}

struct LifetimeStoreTransaction: Equatable {
    let productID: LifetimeProductID
    let originalID: String
    let originalPurchaseDate: Date
    /// When a subscription's current period ends; nil for one-time purchases.
    var expiresAt: Date? = nil

    /// Lifetime purchases never lapse; a subscription only within its period.
    func isActive(at now: Date) -> Bool {
        guard productID.isSubscription else { return true }
        return expiresAt.map { now < $0 } ?? false
    }
}

struct LifetimeStoreSnapshot {
    var entitlements: [LifetimeStoreTransaction] = []
    var firstEarlyPurchase: LifetimeStoreTransaction?
}

enum LifetimePurchaseResult {
    case purchased(LifetimeStoreTransaction)
    case cancelled
    case pending
}

@MainActor
protocol LifetimePurchasing {
    func products() async throws -> [LifetimeStoreProduct]
    func snapshot() async -> LifetimeStoreSnapshot
    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult
    func restore() async throws
    func finish(_ transaction: LifetimeStoreTransaction) async
    /// Every verified transaction of these products as the store signed it,
    /// refunded ones included, so the server can record (or revoke) access.
    func signedTransactions() async -> [SignedStoreTransaction]
    /// Whether this Apple ID's monthly plan will renew at the end of its
    /// period. Apple never lets an app cancel it, so the app keeps asking
    /// someone with lifetime access to do so while this is true.
    func monthlyWillRenew() async -> Bool
    /// Opens the store's own page for cancelling a plan. No app can cancel
    /// one itself, on iOS or Android. Returns when that page is closed.
    func manageSubscriptions(in store: SubscriptionStore) async
}

/// A store transaction in the form the server can verify itself: for the
/// App Store, StoreKit 2's JWS signed by Apple.
struct SignedStoreTransaction: Equatable {
    let originalID: String
    let isRevoked: Bool
    let jws: String
    /// A subscription's period end, so a renewal counts as a change to send.
    var expiresAt: Date? = nil
    /// A subscription's signed renewal info (whether it will be charged
    /// again), so the account's other devices know too.
    var renewalJWS: String? = nil
    var willAutoRenew: Bool? = nil
}

/// Where a monthly plan is billed, and so where it can be cancelled.
enum SubscriptionStore: Equatable {
    case appStore, googlePlay
}

extension LifetimePurchasing {
    func signedTransactions() async -> [SignedStoreTransaction] { [] }
    func monthlyWillRenew() async -> Bool { false }
    func manageSubscriptions(in store: SubscriptionStore) async {}
}

@MainActor
final class StoreKitLifetimePurchases: LifetimePurchasing {
    private var loadedProducts: [String: Product] = [:]

    func products() async throws -> [LifetimeStoreProduct] {
        let products = try await Product.products(for: LifetimeProductID.allCases.map(\.rawValue))
        // A misconfigured paid early-adopter product must never charge someone
        // who selected a free offer. Lifetime products must be non-consumables,
        // the monthly plan an auto-renewing subscription.
        let valid = products.filter { product in
            guard let id = LifetimeProductID(rawValue: product.id) else { return false }
            if id.isSubscription { return product.type == .autoRenewable }
            return product.type == .nonConsumable && (id != .earlyAdopter || product.price == 0)
        }
        loadedProducts = Dictionary(uniqueKeysWithValues: valid.map { ($0.id, $0) })
        return valid.compactMap { product in
            LifetimeProductID(rawValue: product.id).map { LifetimeStoreProduct(id: $0, displayPrice: product.displayPrice) }
        }
    }

    func snapshot() async -> LifetimeStoreSnapshot {
        var snapshot = LifetimeStoreSnapshot()
        for await result in StoreKit.Transaction.currentEntitlements {
            // A subscription is listed here only while it is active (or in
            // Apple's billing grace period).
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  let value = value(transaction) else { continue }
            snapshot.entitlements.append(value)
        }
        // Includes the original claim after refunds/revocations. Restoring the
        // same non-consumable never creates another eligibility window.
        for await result in StoreKit.Transaction.all {
            guard case .verified(let transaction) = result,
                  let value = value(transaction), value.productID == .earlyAdopter else { continue }
            if snapshot.firstEarlyPurchase == nil || value.originalPurchaseDate < snapshot.firstEarlyPurchase!.originalPurchaseDate {
                snapshot.firstEarlyPurchase = value
            }
        }
        return snapshot
    }

    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult {
        guard let product = loadedProducts[id.rawValue] else { throw PurchaseError.unavailable }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil, let value = value(transaction) else {
                throw PurchaseError.unverified
            }
            return .purchased(value)
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw PurchaseError.unverified
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func signedTransactions() async -> [SignedStoreTransaction] {
        var latest: [String: SignedStoreTransaction] = [:]
        var subscriptions: [String: StoreKit.Transaction] = [:]
        for await result in StoreKit.Transaction.all {
            guard case .verified(let transaction) = result,
                  LifetimeProductID(rawValue: transaction.productID) != nil else { continue }
            let id = transaction.originalID.description
            let signed = SignedStoreTransaction(originalID: id, isRevoked: transaction.revocationDate != nil,
                                                jws: result.jwsRepresentation, expiresAt: transaction.expirationDate)
            if let existing = latest[id] {
                if let expiresAt = signed.expiresAt {
                    // A subscription renews under the same original ID: the
                    // period that ends last is the current one.
                    if let current = existing.expiresAt, current > expiresAt { continue }
                } else if existing.isRevoked {
                    // A refund shows up as a revoked transaction; that one wins.
                    continue
                }
            }
            latest[id] = signed
            if signed.expiresAt != nil { subscriptions[id] = transaction }
        }
        // Whether each plan will renew, signed by Apple like the transaction.
        for (id, transaction) in subscriptions {
            guard let status = await transaction.subscriptionStatus,
                  case .verified(let renewal) = status.renewalInfo else { continue }
            latest[id]?.renewalJWS = status.renewalInfo.jwsRepresentation
            latest[id]?.willAutoRenew = renewal.willAutoRenew
        }
        return latest.values.sorted { $0.originalID < $1.originalID }
    }

    func monthlyWillRenew() async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == LifetimeProductID.monthly.rawValue,
                  let status = await transaction.subscriptionStatus,
                  case .verified(let renewal) = status.renewalInfo else { continue }
            return renewal.willAutoRenew
        }
        return false
    }

    func manageSubscriptions(in store: SubscriptionStore) async {
        switch store {
        case .appStore:
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            try? await AppStore.showManageSubscriptions(in: scene)
        case .googlePlay:
            // A plan bought on Android: Google Play's page, in the browser.
            guard let url = URL(string: "https://play.google.com/store/account/subscriptions") else { return }
            await UIApplication.shared.open(url)
        }
    }

    func finish(_ value: LifetimeStoreTransaction) async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  transaction.originalID.description == value.originalID else { continue }
            await transaction.finish()
        }
    }

    private func value(_ transaction: StoreKit.Transaction) -> LifetimeStoreTransaction? {
        guard let productID = LifetimeProductID(rawValue: transaction.productID) else { return nil }
        return LifetimeStoreTransaction(productID: productID, originalID: transaction.originalID.description,
                                        originalPurchaseDate: transaction.originalPurchaseDate,
                                        expiresAt: transaction.expirationDate)
    }

    enum PurchaseError: LocalizedError {
        case unavailable, unverified
        var errorDescription: String? {
            switch self {
            case .unavailable: L10n("This purchase is currently unavailable. Please try again.")
            case .unverified: L10n("Your purchase could not be verified. Please try restoring purchases.")
            }
        }
    }
}
