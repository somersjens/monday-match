import Combine
import Foundation
import StoreKit

@MainActor
final class LifetimeAccessStore: ObservableObject {
    @Published private(set) var products: [LifetimeStoreProduct] = []
    @Published private(set) var ledger = EarlyAccessLedger()
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasPaidAccess = false
    @Published private(set) var hasEarlyEntitlement = false
    @Published private(set) var isRequestingReminder = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var clock = Date()

    private let purchasing: LifetimePurchasing
    private let storage: EarlyAccessLedgerStoring
    private let reminder: EarlyAccessReminderScheduling
    private let now: () -> Date
    private var updatesTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var profileCompletedAt: Date?
    @Published private(set) var isEarlyAccessRevealed = false

    init(purchasing: LifetimePurchasing? = nil,
         storage: EarlyAccessLedgerStoring? = nil,
         reminder: EarlyAccessReminderScheduling? = nil,
         now: @escaping () -> Date = Date.init) {
        self.purchasing = purchasing ?? StoreKitLifetimePurchases()
        self.storage = storage ?? KeychainEarlyAccessLedgerStore()
        self.reminder = reminder ?? EarlyAccessReminder()
        self.now = now
        do { ledger = try self.storage.load() }
        catch { errorMessage = error.localizedDescription }
    }

    deinit {
        updatesTask?.cancel()
        deadlineTask?.cancel()
        refreshTask?.cancel()
    }

    var canOfferEarlyAccess: Bool {
        if isEarlyAccessRevealed { return true }
        return ledger.canOfferEarlyAccess(at: clock)
    }

    var hasAccess: Bool {
        if hasPaidAccess { return true }
        if ledger.reactivatedAt != nil {
            return ledger.permitsAccess(at: clock, profileCompletedAt: profileCompletedAt)
        }
        return hasEarlyEntitlement && ledger.permitsAccess(at: clock, profileCompletedAt: profileCompletedAt)
    }

    func product(_ id: LifetimeProductID) -> LifetimeStoreProduct? { products.first { $0.id == id } }

    func start() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await self.refresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    if case .verified(let transaction) = result,
                       LifetimeProductID(rawValue: transaction.productID) != nil {
                        await self?.refresh()
                        // finish only after durable delivery, so a failed Keychain
                        // write can be retried by StoreKit on the next launch.
                        if self?.errorMessage == nil { await transaction.finish() }
                    }
                }
            }
        }
    }

    func refresh() async {
        clock = now()
        do { products = try await purchasing.products() }
        catch { products = []; errorMessage = error.localizedDescription }
        let snapshot = await purchasing.snapshot()
        hasPaidAccess = snapshot.entitlements.contains { $0.productID == .lifetime }
        hasEarlyEntitlement = snapshot.entitlements.contains { $0.productID == .earlyAdopter }
        if let first = snapshot.firstEarlyPurchase {
            var updated = ledger
            updated.register(originalID: first.originalID, purchasedAt: first.originalPurchaseDate)
            save(updated)
        }
        isReady = true
        updateCompletion(profileCompletedAt)
        await updateReminder()
        scheduleDeadlineCheck()
    }

    /// Called both on profile completion and on launch, before exposing the app.
    func updateCompletion(_ date: Date?) {
        profileCompletedAt = date
        clock = now()
        if ledger.completedInTime(date), let date,
           ledger.completedAt == nil || date < ledger.completedAt! {
            var updated = ledger
            updated.completedAt = date
            save(updated)
        }
        if hasPaidAccess || ledger.completedInTime(ledger.completedAt) || ledger.completedInTime(date) {
            reminder.cancel()
        }
    }

    func setReminderEnabled(_ enabled: Bool) async {
        guard !isRequestingReminder else { return }
        isRequestingReminder = true
        defer { isRequestingReminder = false }
        do {
            if enabled, try await reminder.requestPermission() == false {
                notice = L10n("Notifications are off. You can allow them in Settings to receive your reminder.")
                return
            }
            var updated = ledger
            updated.reminderEnabled = enabled
            guard save(updated) else { return }
            await updateReminder()
        } catch { errorMessage = error.localizedDescription }
    }

    func continueWith(_ id: LifetimeProductID) async -> Bool {
        guard !isBusy else { return false }
        clock = now()
        guard id != .earlyAdopter || canOfferEarlyAccess else { return false }
        if hasPaidAccess || (id == .earlyAdopter && hasAccess) {
            isEarlyAccessRevealed = false
            return true
        }
        isBusy = true
        errorMessage = nil
        notice = nil
        defer { isBusy = false }
        let previousRequest = ledger.requestedAt
        do {
            if id == .earlyAdopter {
                var updated = ledger
                updated.requestedAt = previousRequest ?? now() // Keep the first Continue while approval is pending.
                guard save(updated) else { return false }
                if isEarlyAccessRevealed {
                    updated.reactivatedAt = now()
                    updated.completedAt = nil
                    updated.requestedAt = nil
                    guard save(updated) else { return false }
                    isEarlyAccessRevealed = false
                    scheduleDeadlineCheck()
                    await updateReminder()
                    return true
                }
            }
            switch try await purchasing.purchase(id) {
            case .purchased(let transaction):
                if transaction.productID == .earlyAdopter {
                    var updated = ledger
                    updated.register(originalID: transaction.originalID, purchasedAt: transaction.originalPurchaseDate)
                    guard save(updated) else { return false }
                    hasEarlyEntitlement = true
                } else { hasPaidAccess = true }
                await purchasing.finish(transaction)
                clock = now()
                scheduleDeadlineCheck()
                await updateReminder()
                return hasAccess
            case .cancelled:
                if id == .earlyAdopter { restorePendingRequest(previousRequest) }
                return false
            case .pending:
                notice = L10n("Your purchase is awaiting approval. Access will unlock once Apple confirms it.")
                return false
            }
        } catch {
            if id == .earlyAdopter { restorePendingRequest(previousRequest) }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await purchasing.restore()
            await refresh()
            if !hasAccess {
                notice = L10n("No active access found. An expired early-adopter offer cannot be claimed again.")
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Hidden reactivation is deliberately available in production as well.
    /// Revealing alone grants nothing; Continue saves the new seven-day window.
    func revealEarlyAccess() {
        guard !isBusy else { return }
        isEarlyAccessRevealed = true
    }

    @discardableResult
    private func save(_ updated: EarlyAccessLedger) -> Bool {
        do { try storage.save(updated); ledger = updated; return true }
        catch { errorMessage = error.localizedDescription; return false }
    }

    private func restorePendingRequest(_ previousRequest: Date?) {
        var updated = ledger
        updated.requestedAt = previousRequest
        save(updated)
    }

    private func updateReminder() async {
        guard ledger.reminderEnabled, !hasPaidAccess,
              !ledger.completedInTime(ledger.completedAt), !ledger.completedInTime(profileCompletedAt),
              let date = ledger.reminderDate, date > now() else {
            reminder.cancel()
            return
        }
        do { try await reminder.schedule(at: date, now: now()) }
        catch { errorMessage = L10n("Your reminder could not be scheduled. Please try enabling it again.") }
    }

    private func scheduleDeadlineCheck() {
        deadlineTask?.cancel()
        guard let deadline = ledger.deadline, deadline > now(), !hasPaidAccess else { return }
        let delay = deadline.timeIntervalSince(now())
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled else { return }
            self?.clock = self?.now() ?? Date()
        }
    }
}
