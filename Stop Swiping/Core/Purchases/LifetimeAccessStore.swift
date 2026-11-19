import Combine
import Foundation
import StoreKit

@MainActor
final class LifetimeAccessStore: ObservableObject {
    @Published private(set) var products: [LifetimeStoreProduct] = []
    @Published private(set) var ledger = EarlyAccessLedger()
    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    /// What StoreKit grants this Apple ID on this device.
    @Published private(set) var storeEntitlements: [LifetimeStoreTransaction] = []
    /// What the signed-in account owns according to the server, from any
    /// device or store. Kept on the phone so access holds offline and at launch.
    @Published private(set) var accountEntitlements: [AccountEntitlement]
    /// When the half-price lifetime offer was last closed; it returns a month later.
    @Published private(set) var subscriberOfferDismissedAt: Date?
    /// Set once lifetime access was bought while a monthly plan still runs:
    /// Apple never ends that plan for the app, so the home screen asks the
    /// person to cancel it. Lives here because the offer card disappears the
    /// moment the purchase succeeds.
    @Published var asksToCancelSubscription = false
    /// This Apple ID's monthly plan is set to renew.
    @Published private(set) var monthlyStillRenews = false
    /// Counts the times the account's entitlements granted access this
    /// phone didn't have, for screens built before they arrived.
    @Published private(set) var accountAccessArrivals = 0
    @Published private(set) var isRequestingReminder = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var clock = Date()

    private let purchasing: LifetimePurchasing
    private let storage: EarlyAccessLedgerStoring
    private let reminder: EarlyAccessReminderScheduling
    private let now: () -> Date
    private let defaults: UserDefaults
    /// When the account's entitlements were last read from the server.
    private var accountCheckedAt: Date?
    private var updatesTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var profileCompletedAt: Date?
    /// Records purchases against the signed-in account; nil without one.
    private var serverSync: StoreEntitlementSync?
    @Published private(set) var isEarlyAccessRevealed = false

    init(purchasing: LifetimePurchasing? = nil,
         storage: EarlyAccessLedgerStoring? = nil,
         reminder: EarlyAccessReminderScheduling? = nil,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.purchasing = purchasing ?? StoreKitLifetimePurchases()
        self.storage = storage ?? KeychainEarlyAccessLedgerStore()
        self.reminder = reminder ?? EarlyAccessReminder()
        self.defaults = defaults
        self.now = now
        accountEntitlements = defaults.data(forKey: Self.accountEntitlementsKey)
            .flatMap { try? JSONDecoder().decode([AccountEntitlement].self, from: $0) } ?? []
        subscriberOfferDismissedAt = defaults.object(forKey: Self.subscriberOfferDismissedKey) as? Date
        do { ledger = try self.storage.load() }
        catch { errorMessage = error.localizedDescription }
    }

    deinit {
        updatesTask?.cancel()
        deadlineTask?.cancel()
        refreshTask?.cancel()
    }

    static let accountEntitlementsKey = "storeEntitlements.account.v1"
    static let subscriberOfferDismissedKey = "lifetimeOffer.subscriberDismissedAt.v1"
    /// How long the account's entitlements are trusted before asking again,
    /// while they grant access. Without access they are asked for right away.
    static let accountRecheckInterval: TimeInterval = 12 * 60 * 60

    var canOfferEarlyAccess: Bool {
        if isEarlyAccessRevealed { return true }
        // A claim made with the account elsewhere (another Apple ID, Android)
        // counts as well: the free plan is one per person, not per device.
        return ledger.canOfferEarlyAccess(at: clock) && (accountEarlyLedger?.canOfferEarlyAccess(at: clock) ?? true)
    }

    /// Lifetime access bought on this Apple ID or by the account anywhere.
    var hasLifetimeAccess: Bool {
        storeEntitlements.contains { $0.productID.isLifetime }
            || accountEntitlements.contains { $0.productID.isLifetime && !$0.revoked }
    }

    /// A monthly plan in its current period, here or on the account.
    var hasActiveSubscription: Bool {
        storeEntitlements.contains { $0.productID.isSubscription && $0.isActive(at: clock) }
            || accountEntitlements.contains { $0.productID.isSubscription && $0.isActive(at: clock) }
    }

    var hasPaidAccess: Bool { hasLifetimeAccess || hasActiveSubscription }

    private var hasEarlyEntitlement: Bool { storeEntitlements.contains { $0.productID == .earlyAdopter } }

    /// The free plan as the account recorded it: the same seven days, from
    /// the server's purchase date.
    private var accountEarlyLedger: EarlyAccessLedger? {
        guard let first = accountEntitlements.filter({ $0.productID == .earlyAdopter && !$0.revoked })
            .map(\.purchasedAt).min() else { return nil }
        var ledger = EarlyAccessLedger()
        ledger.startedAt = first
        return ledger
    }

    /// The half-price lifetime offer on the home screen: for monthly
    /// subscribers only, and a month after it was last closed.
    var offersSubscriberLifetime: Bool {
        guard hasActiveSubscription, !hasLifetimeAccess, product(.subscriberLifetime) != nil else { return false }
        guard let dismissed = subscriberOfferDismissedAt,
              let due = Calendar.current.date(byAdding: .month, value: 1, to: dismissed) else { return true }
        return clock >= due
    }

    /// With lifetime access, a monthly plan that will still be charged, and
    /// where to cancel it: this Apple ID's own plan (StoreKit knows), or one
    /// the account pays for elsewhere (another Apple ID, Google Play; the
    /// server knows). The home screen keeps asking until it no longer renews.
    var subscriptionToCancel: SubscriptionStore? {
        guard hasLifetimeAccess else { return nil }
        if monthlyStillRenews { return .appStore }
        // This Apple ID's own plan was answered by StoreKit just now; the
        // server's copy of it may lag behind.
        let ownPlan = storeEntitlements.contains { $0.productID.isSubscription }
        return accountEntitlements.first { entitlement in
            entitlement.productID.isSubscription && entitlement.isActive(at: clock) && entitlement.autoRenews == true
                && !(ownPlan && entitlement.subscriptionStore == .appStore)
        }?.subscriptionStore
    }

    var remindsToCancelSubscription: Bool { subscriptionToCancel != nil }

    /// The plan to cancel is billed to another Apple ID: this phone can't
    /// open it, the person cancels it on the device they subscribed with.
    var cancelsOnAnotherAppleID: Bool { subscriptionToCancel == .appStore && !monthlyStillRenews }

    /// Opens the store's page for cancelling, then checks what changed.
    func manageSubscription() async {
        guard let store = subscriptionToCancel else { return }
        await purchasing.manageSubscriptions(in: store)
        await refresh()
        // A Google Play plan is only known through the server.
        if store == .googlePlay { await loadAccountEntitlements() }
    }

    func dismissSubscriberOffer() {
        let date = now()
        defaults.set(date, forKey: Self.subscriberOfferDismissedKey)
        subscriberOfferDismissedAt = date
    }

    var hasAccess: Bool {
        if hasPaidAccess { return true }
        if accountEarlyLedger?.permitsAccess(at: clock, profileCompletedAt: profileCompletedAt) == true { return true }
        if ledger.reactivatedAt != nil {
            return ledger.permitsAccess(at: clock, profileCompletedAt: profileCompletedAt)
        }
        return hasEarlyEntitlement && ledger.permitsAccess(at: clock, profileCompletedAt: profileCompletedAt)
    }

    /// The early-adopter deadline the questionnaire counts down to. Nil with
    /// lifetime access, without an early-adopter window or once it has passed.
    var questionnaireDeadline: Date? {
        guard !hasPaidAccess, let deadline = ledger.deadline, clock < deadline else { return nil }
        return deadline
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
        // Entitlements are on the device; prices come from the App Store. Access
        // is known, and the app can open, before the prices arrive.
        let snapshot = await purchasing.snapshot()
        storeEntitlements = snapshot.entitlements
        monthlyStillRenews = storeEntitlements.contains { $0.productID.isSubscription }
            ? await purchasing.monthlyWillRenew() : false
        if let first = snapshot.firstEarlyPurchase {
            var updated = ledger
            updated.register(originalID: first.originalID, purchasedAt: first.originalPurchaseDate)
            save(updated)
        }
        isReady = true
        updateCompletion(profileCompletedAt)
        do { products = try await purchasing.products() }
        catch { products = []; errorMessage = error.localizedDescription }
        await updateReminder()
        scheduleDeadlineCheck()
        // Something new on the server (a purchase, a cancelled plan): read
        // back what the account owns, so its other devices' view is current too.
        let sent = await serverSync?.syncIfNeeded() ?? false
        if serverSync != nil, sent || needsAccountCheck { await loadAccountEntitlements() }
    }

    /// Once there is an account, its purchases are recorded on the server
    /// (only when something changed since the last time), and what it owns
    /// from other devices or stores is read back.
    func connectServer(_ recorder: StoreEntitlementRecording?) async {
        guard let recorder else { return }
        if serverSync == nil { serverSync = StoreEntitlementSync(recorder: recorder, purchasing: purchasing) }
        await serverSync?.syncIfNeeded()
        // Signing in and the account appearing both connect; one read will do.
        if let accountCheckedAt, now().timeIntervalSince(accountCheckedAt) < 60 { return }
        await loadAccountEntitlements()
    }

    /// Another account may sign in next: nothing of this one stays behind.
    func disconnectServer() {
        serverSync?.accountSignedOut()
        serverSync = nil
        accountCheckedAt = nil
        setAccountEntitlements([])
    }

    /// Access that rests on the account alone is checked again on every
    /// return to the app; otherwise twice a day is plenty.
    private var needsAccountCheck: Bool {
        guard let accountCheckedAt else { return true }
        let localAccess = storeEntitlements.contains { $0.isActive(at: clock) }
        return !localAccess && now().timeIntervalSince(accountCheckedAt) > Self.accountRecheckInterval
            || !hasAccess
    }

    private func loadAccountEntitlements() async {
        guard let serverSync else { return }
        // Sign-in waits for this answer, so a slow network gets five seconds;
        // the next return to the app asks again.
        let request = Task { await serverSync.accountEntitlements() }
        let timeout = Task { try? await Task.sleep(for: .seconds(5)); request.cancel() }
        defer { timeout.cancel() }
        guard let entitlements = await request.value else { return }
        let hadAccess = hasAccess
        accountCheckedAt = now()
        clock = now()
        setAccountEntitlements(entitlements)
        scheduleDeadlineCheck()
        if !hadAccess && hasAccess { accountAccessArrivals += 1 }
    }

    private func setAccountEntitlements(_ entitlements: [AccountEntitlement]) {
        guard entitlements != accountEntitlements else { return }
        accountEntitlements = entitlements
        if entitlements.isEmpty { defaults.removeObject(forKey: Self.accountEntitlementsKey) }
        else if let data = try? JSONEncoder().encode(entitlements) { defaults.set(data, forKey: Self.accountEntitlementsKey) }
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
        guard id != .subscriberLifetime || hasActiveSubscription else { return false }
        if (hasPaidAccess && id != .subscriberLifetime) || (id == .earlyAdopter && hasAccess) {
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
                }
                storeEntitlements.removeAll { $0.originalID == transaction.originalID }
                storeEntitlements.append(transaction)
                if transaction.productID.isSubscription { monthlyStillRenews = true }
                await purchasing.finish(transaction)
                clock = now()
                scheduleDeadlineCheck()
                await updateReminder()
                // The account owns it from now on, also on its other devices.
                await serverSync?.syncIfNeeded()
                if transaction.productID.isLifetime && hasActiveSubscription { asksToCancelSubscription = true }
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

    /// Wakes up when access may end: the free plan's deadline, or the end of
    /// a monthly period (StoreKit then usually has the renewal already).
    private func scheduleDeadlineCheck() {
        deadlineTask?.cancel()
        let current = now()
        var moments: [Date] = []
        if !hasLifetimeAccess {
            if !hasActiveSubscription { moments += [ledger.deadline, accountEarlyLedger?.deadline].compactMap { $0 } }
            moments += (storeEntitlements.compactMap(\.expiresAt) + accountEntitlements.compactMap(\.expiresAt))
        }
        guard let next = moments.filter({ $0 > current }).min() else { return }
        let renews = !hasLifetimeAccess && hasActiveSubscription
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, next.timeIntervalSince(current))))
            guard !Task.isCancelled, let self else { return }
            self.clock = self.now()
            // A renewal arrives through StoreKit, or through the server for
            // a plan bought on another device.
            // A task of its own: this one is cancelled when refresh reschedules.
            if renews { Task { await self.refresh() } }
        }
    }
}
