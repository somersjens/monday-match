import Foundation
import StoreKit

struct LifetimeStoreProduct: Equatable {
    let id: LifetimeProductID
    let displayPrice: String
}

struct LifetimeStoreTransaction: Equatable {
    let productID: LifetimeProductID
    let originalID: String
    let originalPurchaseDate: Date
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
}

@MainActor
final class StoreKitLifetimePurchases: LifetimePurchasing {
    private var loadedProducts: [String: Product] = [:]

    func products() async throws -> [LifetimeStoreProduct] {
        let products = try await Product.products(for: LifetimeProductID.allCases.map(\.rawValue))
        // A misconfigured paid early-adopter product must never charge someone
        // who selected a free offer. Both products must be non-consumables.
        let valid = products.filter {
            $0.type == .nonConsumable && ($0.id != LifetimeProductID.earlyAdopter.rawValue || $0.price == 0)
        }
        loadedProducts = Dictionary(uniqueKeysWithValues: valid.map { ($0.id, $0) })
        return valid.compactMap { product in
            LifetimeProductID(rawValue: product.id).map { LifetimeStoreProduct(id: $0, displayPrice: product.displayPrice) }
        }
    }

    func snapshot() async -> LifetimeStoreSnapshot {
        var snapshot = LifetimeStoreSnapshot()
        for await result in StoreKit.Transaction.currentEntitlements {
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
                                        originalPurchaseDate: transaction.originalPurchaseDate)
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
