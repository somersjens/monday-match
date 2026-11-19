import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class LifetimeAccessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_491_200)
    /// Every store gets its own defaults, so nothing the app host saved
    /// (an account's entitlements, a closed offer) leaks into a test.
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites.removeAll()
        super.tearDown()
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "LifetimeAccessTests-\(UUID())"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    func testExactDeadlineAndCompletionBoundary() {
        var ledger = EarlyAccessLedger()
        ledger.register(originalID: "first", purchasedAt: start)
        XCTAssertTrue(ledger.permitsAccess(at: start.addingTimeInterval(7 * 86_400 - 1), profileCompletedAt: nil))
        XCTAssertFalse(ledger.permitsAccess(at: start.addingTimeInterval(7 * 86_400), profileCompletedAt: nil))
        XCTAssertFalse(ledger.canOfferEarlyAccess(at: start.addingTimeInterval(8 * 86_400)))
        XCTAssertTrue(ledger.permitsAccess(at: start.addingTimeInterval(30 * 86_400),
                                         profileCompletedAt: start.addingTimeInterval(7 * 86_400 - 1)))
        XCTAssertFalse(ledger.permitsAccess(at: start.addingTimeInterval(30 * 86_400),
                                          profileCompletedAt: start.addingTimeInterval(7 * 86_400)))
        XCTAssertFalse(ledger.completedInTime(start.addingTimeInterval(-1)))
    }

    func testRestoreOrRepeatedClaimNeverRestartsDeadline() {
        var ledger = EarlyAccessLedger()
        ledger.requestedAt = start
        ledger.register(originalID: "first", purchasedAt: start.addingTimeInterval(30))
        XCTAssertEqual(ledger.startedAt, start)
        ledger.requestedAt = start.addingTimeInterval(10 * 86_400)
        ledger.register(originalID: "first", purchasedAt: start.addingTimeInterval(30))
        XCTAssertEqual(ledger.startedAt, start)
        ledger.register(originalID: "other", purchasedAt: start.addingTimeInterval(20 * 86_400))
        XCTAssertEqual(ledger.startedAt, start)
    }

    func testElapsedReminderAcrossDSTAndTimeZones() throws {
        let formatter = ISO8601DateFormatter()
        let beforeDST = try XCTUnwrap(formatter.date(from: "2026-10-23T10:30:00Z"))
        var ledger = EarlyAccessLedger()
        ledger.register(originalID: "first", purchasedAt: beforeDST)
        XCTAssertEqual(ledger.reminderDate, formatter.date(from: "2026-10-29T10:30:00Z"))
        XCTAssertEqual(ledger.deadline, formatter.date(from: "2026-10-30T10:30:00Z"))
        for zone in ["Europe/Amsterdam", "America/New_York", "Asia/Tokyo"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            XCTAssertEqual(ledger.reminderDate?.timeIntervalSince(beforeDST), 518_400)
            XCTAssertNotNil(calendar.dateComponents([.hour], from: try XCTUnwrap(ledger.reminderDate)).hour)
        }
    }

    func testReminderOffByDefaultAndDenialDoesNotEnableIt() async {
        let reminder = FakeReminder()
        reminder.permission = false
        let store = makeStore(reminder: reminder)
        XCTAssertFalse(store.ledger.reminderEnabled)
        XCTAssertEqual(reminder.permissionRequests, 0)
        await store.setReminderEnabled(true)
        XCTAssertEqual(reminder.permissionRequests, 1)
        XCTAssertFalse(store.ledger.reminderEnabled)
        XCTAssertTrue(reminder.scheduled.isEmpty)
        XCTAssertNotNil(store.notice)
    }

    func testPurchaseSchedulesFromContinueAndCompletionCancelsReminder() async {
        let purchasing = FakePurchases()
        purchasing.result = .purchased(transaction(at: start.addingTimeInterval(45)))
        let reminder = FakeReminder()
        let store = makeStore(purchasing: purchasing, reminder: reminder)
        await store.start()
        await store.setReminderEnabled(true)
        XCTAssertTrue(reminder.scheduled.isEmpty)
        let continued = await store.continueWith(.earlyAdopter)
        XCTAssertTrue(continued)
        XCTAssertEqual(store.ledger.startedAt, start)
        XCTAssertEqual(reminder.scheduled.last, start.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(purchasing.finished, 1)
        store.updateCompletion(start.addingTimeInterval(100))
        XCTAssertEqual(store.ledger.completedAt, start.addingTimeInterval(100))
        XCTAssertTrue(reminder.scheduled.isEmpty)
    }

    func testExpiredRestoredClaimOnlyAllowsPaidPurchase() async {
        let purchasing = FakePurchases()
        let old = transaction(at: start.addingTimeInterval(-8 * 86_400))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [old], firstEarlyPurchase: old)
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertFalse(store.hasAccess)
        XCTAssertFalse(store.canOfferEarlyAccess)
        let early = await store.continueWith(.earlyAdopter)
        XCTAssertFalse(early)
        XCTAssertEqual(purchasing.purchaseCalls, [])
        purchasing.result = .purchased(LifetimeStoreTransaction(productID: .lifetime, originalID: "paid", originalPurchaseDate: start))
        let paid = await store.continueWith(.lifetime)
        XCTAssertTrue(paid)
        XCTAssertEqual(purchasing.purchaseCalls, [.lifetime])
        XCTAssertTrue(store.hasPaidAccess)
    }

    func testCancelledPendingAndFailedPersistenceNeverGrantAccess() async {
        let purchasing = FakePurchases()
        let storage = FakeLedgerStore()
        let store = makeStore(purchasing: purchasing, storage: storage)
        await store.start()
        purchasing.result = .cancelled
        let cancelled = await store.continueWith(.earlyAdopter)
        XCTAssertFalse(cancelled)
        XCTAssertNil(store.ledger.startedAt)
        XCTAssertNil(store.ledger.requestedAt)
        purchasing.result = .pending
        let pending = await store.continueWith(.earlyAdopter)
        XCTAssertFalse(pending)
        XCTAssertNotNil(store.ledger.requestedAt)
        XCTAssertFalse(store.hasAccess)
        storage.fails = true
        purchasing.result = .purchased(transaction(at: start))
        let failed = await store.continueWith(.earlyAdopter)
        XCTAssertFalse(failed)
        XCTAssertFalse(store.hasAccess)
        XCTAssertEqual(purchasing.finished, 0)
    }

    func testPendingApprovalKeepsOriginalContinueTimeAcrossRetries() async {
        let purchasing = FakePurchases()
        let storage = FakeLedgerStore()
        storage.ledger.requestedAt = start.addingTimeInterval(-3600)
        let store = makeStore(purchasing: purchasing, storage: storage)
        purchasing.result = .pending
        let pending = await store.continueWith(.earlyAdopter)
        XCTAssertFalse(pending)
        XCTAssertEqual(store.ledger.requestedAt, start.addingTimeInterval(-3600))
        purchasing.result = .cancelled
        let cancelledPaid = await store.continueWith(.lifetime)
        XCTAssertFalse(cancelledPaid)
        XCTAssertEqual(store.ledger.requestedAt, start.addingTimeInterval(-3600))
        purchasing.result = .purchased(transaction(at: start))
        let approved = await store.continueWith(.earlyAdopter)
        XCTAssertTrue(approved)
        XCTAssertEqual(store.ledger.startedAt, start.addingTimeInterval(-3600))
    }

    func testRelaunchPreservesCompletedLifetimeAndDoesNotRescheduleReminder() async {
        let storage = FakeLedgerStore()
        storage.ledger.register(originalID: "first", purchasedAt: start.addingTimeInterval(-20 * 86_400))
        storage.ledger.completedAt = start.addingTimeInterval(-19 * 86_400)
        storage.ledger.reminderEnabled = true
        let purchasing = FakePurchases()
        let early = transaction(at: start.addingTimeInterval(-20 * 86_400))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
        let reminder = FakeReminder()
        let store = makeStore(purchasing: purchasing, storage: storage, reminder: reminder)
        await store.start()
        XCTAssertTrue(store.hasAccess)
        XCTAssertTrue(reminder.scheduled.isEmpty)
        // Refunded entitlements must revoke access even with cached completion.
        purchasing.state.entitlements = []
        await store.refresh()
        XCTAssertFalse(store.hasAccess)
    }

    func testPurchasingLifetimeDuringEarlyAccessReallyPurchasesLifetime() async {
        let purchasing = FakePurchases()
        let early = transaction(at: start)
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertTrue(store.hasAccess)
        purchasing.result = .purchased(LifetimeStoreTransaction(productID: .lifetime, originalID: "paid", originalPurchaseDate: start))
        let paid = await store.continueWith(.lifetime)
        XCTAssertTrue(paid)
        XCTAssertEqual(purchasing.purchaseCalls, [.lifetime])
    }

    func testHiddenHoldRevealsOfferWithoutChangingDeadlineUntilContinue() async {
        let storage = FakeLedgerStore()
        let originalStart = start.addingTimeInterval(-8 * 86_400)
        storage.ledger.register(originalID: "first", purchasedAt: originalStart)
        let purchasing = FakePurchases()
        let original = transaction(at: originalStart)
        purchasing.state = LifetimeStoreSnapshot(entitlements: [original], firstEarlyPurchase: original)
        let store = makeStore(purchasing: purchasing, storage: storage)
        await store.start()
        let oldDeadline = store.ledger.deadline
        store.revealEarlyAccess()
        XCTAssertTrue(store.canOfferEarlyAccess)
        XCTAssertFalse(store.hasAccess)
        XCTAssertEqual(store.ledger.deadline, oldDeadline)
        let continued = await store.continueWith(.earlyAdopter)
        XCTAssertTrue(continued)
        XCTAssertEqual(store.ledger.effectiveStartedAt, start)
        XCTAssertFalse(store.isEarlyAccessRevealed)
        XCTAssertEqual(store.ledger.startedAt, originalStart)
        XCTAssertTrue(purchasing.purchaseCalls.isEmpty)

        // Restoring Apple's old transaction must preserve the explicit reset.
        await store.refresh()
        XCTAssertEqual(store.ledger.effectiveStartedAt, start)
        let relaunched = makeStore(purchasing: purchasing, storage: storage)
        await relaunched.start()
        XCTAssertTrue(relaunched.hasAccess)
        XCTAssertEqual(relaunched.ledger.deadline, start.addingTimeInterval(7 * 86_400))

        let expired = LifetimeAccessStore(purchasing: purchasing, storage: storage, reminder: FakeReminder(),
                                          defaults: freshDefaults(),
                                          now: { self.start.addingTimeInterval(8 * 86_400) })
        await expired.start()
        XCTAssertFalse(expired.hasAccess)
        XCTAssertFalse(expired.canOfferEarlyAccess)
    }

    func testReactivatedAccessKeepsTimelyCompletionAcrossRelaunch() async {
        let storage = FakeLedgerStore()
        let store = makeStore(storage: storage)
        store.revealEarlyAccess()
        let continued = await store.continueWith(.earlyAdopter)
        XCTAssertTrue(continued)
        store.updateCompletion(start.addingTimeInterval(100))
        let relaunched = LifetimeAccessStore(purchasing: FakePurchases(), storage: storage, reminder: FakeReminder(),
                                             defaults: freshDefaults(),
                                             now: { self.start.addingTimeInterval(30 * 86_400) })
        await relaunched.start()
        XCTAssertTrue(relaunched.hasAccess)
    }

    func testAccessScreenRendersInBothLanguagesAndAfterExpiry() async throws {
        for (name, language, expired, width, height) in [
            ("early-en", AppLanguage.english, false, 393.0, 852.0),
            ("early-nl", AppLanguage.dutch, false, 393.0, 852.0),
            ("expired", AppLanguage.english, true, 393.0, 852.0),
            ("expired-nl", AppLanguage.dutch, true, 393.0, 852.0),
            ("compact", AppLanguage.english, false, 375.0, 812.0),
            ("small", AppLanguage.english, false, 320.0, 568.0)
        ] {
            AppLanguageSettings.shared.language = language
            defer { AppLanguageSettings.shared.language = .english }
            let purchasing = FakePurchases()
            if expired {
                let early = transaction(at: start.addingTimeInterval(-8 * 86_400))
                purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
            }
            let store = makeStore(purchasing: purchasing)
            await store.start()
            let screen = EarlyAccessView(access: store, onContinue: {}, onBack: {})
                .environment(\.locale, language.locale)
            try await render(screen, name: name, width: width, height: height)
        }
    }

    func testSubscriberOfferCardRendersAboveAutoMatching() async throws {
        let purchasing = FakePurchases()
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400))])
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertTrue(store.offersSubscriberLifetime)
        for (name, language, width) in [("offer-en", AppLanguage.english, 393.0), ("offer-nl", AppLanguage.dutch, 393.0),
                                         ("offer-small", AppLanguage.dutch, 320.0)] {
            AppLanguageSettings.shared.language = language
            defer { AppLanguageSettings.shared.language = .english }
            let state = ProfileCreationState(today: .init(year: 2026, month: 11, day: 19), applicationLanguage: language.rawValue)
            let model = ProfileCreationViewModel(store: InMemoryProfileCreationStore(state: state), repository: nil)
            let screen = VStack(spacing: 12) {
                SubscriberLifetimeOfferCard(access: store)
                AutoMatchingCard(viewModel: model) {}
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("WelcomeBackground"))
            .environment(\.locale, language.locale)
            .preferredColorScheme(.dark)
            try await render(screen, name: name, width: width, height: 220)
        }

        let renewing = FakePurchases()
        renewing.state = LifetimeStoreSnapshot(entitlements: [
            monthly(until: start.addingTimeInterval(20 * 86_400)),
            LifetimeStoreTransaction(productID: .subscriberLifetime, originalID: "half", originalPurchaseDate: start)])
        renewing.willRenew = true
        let paid = makeStore(purchasing: renewing)
        await paid.start()
        XCTAssertTrue(paid.remindsToCancelSubscription)
        let recorder = FakeRecorder()
        recorder.owned = [AccountEntitlement(productID: .monthly, purchasedAt: start,
                                             expiresAt: start.addingTimeInterval(20 * 86_400), revoked: false,
                                             store: "app_store", autoRenews: true)]
        let lifetimeOnly = FakePurchases()
        lifetimeOnly.state = LifetimeStoreSnapshot(entitlements: [
            LifetimeStoreTransaction(productID: .lifetime, originalID: "life", originalPurchaseDate: start)])
        let elsewhere = makeStore(purchasing: lifetimeOnly)
        await elsewhere.start()
        await elsewhere.connectServer(recorder)
        XCTAssertTrue(elsewhere.cancelsOnAnotherAppleID)
        for (name, language, store, width, size) in [
            ("cancel-en", AppLanguage.english, paid, 393.0, DynamicTypeSize.large),
            ("cancel-nl", AppLanguage.dutch, paid, 393.0, .large),
            ("cancel-nl-small", AppLanguage.dutch, paid, 320.0, .large),
            ("cancel-nl-xxxl", AppLanguage.dutch, paid, 320.0, .xxxLarge),
            ("cancel-elsewhere-nl", AppLanguage.dutch, elsewhere, 320.0, .large)
        ] {
            AppLanguageSettings.shared.language = language
            defer { AppLanguageSettings.shared.language = .english }
            let screen = VStack { CancelSubscriptionCard(access: store); Spacer() }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("WelcomeBackground"))
                .environment(\.locale, language.locale)
                .dynamicTypeSize(size)
                .preferredColorScheme(.dark)
            try await render(screen, name: name, width: width, height: 300)
        }
    }

    private func render<Screen: View>(_ screen: Screen, name: String, width: Double, height: Double) async throws {
        // XCTest may begin before SwiftUI connects its first scene.
        for _ in 0..<50 {
            if UIApplication.shared.connectedScenes.contains(where: { $0 is UIWindowScene }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let previous = scene.windows.first(where: \.isKeyWindow)
        let container = UIViewController()
        let host = UIHostingController(rootView: screen)
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.addChild(host)
        container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.widthAnchor.constraint(equalToConstant: width),
            host.view.heightAnchor.constraint(equalToConstant: height),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor)
        ])
        host.didMove(toParent: container)
        container.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(1300))
        host.view.layoutIfNeeded()
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
        let attachment = XCTAttachment(image: image)
        attachment.name = "Access-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("access-\(name).png")
        try XCTUnwrap(image.pngData()).write(to: path)
        print("ACCESS_RENDER \(path.path)")
        XCTAssertEqual(image.size, size)
    }

    private func transaction(at date: Date) -> LifetimeStoreTransaction {
        LifetimeStoreTransaction(productID: .earlyAdopter, originalID: "first", originalPurchaseDate: date)
    }

    private func makeStore(purchasing: FakePurchases? = nil, storage: FakeLedgerStore? = nil,
                           reminder: FakeReminder? = nil, defaults: UserDefaults? = nil,
                           now: (() -> Date)? = nil) -> LifetimeAccessStore {
        LifetimeAccessStore(purchasing: purchasing ?? FakePurchases(), storage: storage ?? FakeLedgerStore(),
                            reminder: reminder ?? FakeReminder(), defaults: defaults ?? freshDefaults(),
                            now: now ?? { self.start })
    }

    private func monthly(until end: Date) -> LifetimeStoreTransaction {
        LifetimeStoreTransaction(productID: .monthly, originalID: "sub", originalPurchaseDate: start, expiresAt: end)
    }

    // MARK: - Access from the account (another phone, Apple ID or Android)

    func testLifetimeBoughtElsewhereUnlocksAfterSignIn() async {
        let recorder = FakeRecorder()
        recorder.owned = [AccountEntitlement(productID: .lifetime, purchasedAt: start.addingTimeInterval(-90 * 86_400),
                                             expiresAt: nil, revoked: false)]
        let defaults = freshDefaults()
        let store = makeStore(defaults: defaults)
        await store.start()
        XCTAssertFalse(store.hasAccess, "Nothing on this Apple ID")
        await store.connectServer(recorder)
        XCTAssertTrue(store.hasAccess)
        XCTAssertTrue(store.hasLifetimeAccess)

        // Kept on the phone: the next launch opens straight into the app.
        let relaunched = makeStore(defaults: defaults)
        XCTAssertTrue(relaunched.hasAccess)
        // Signing out leaves nothing of the account behind.
        relaunched.disconnectServer()
        XCTAssertFalse(relaunched.hasAccess)
        XCTAssertFalse(makeStore(defaults: defaults).hasAccess)
    }

    func testRefundedOrUnknownAccountPurchasesGrantNothing() async {
        let recorder = FakeRecorder()
        recorder.owned = [AccountEntitlement(productID: .lifetime, purchasedAt: start, expiresAt: nil, revoked: true)]
        let store = makeStore()
        await store.connectServer(recorder)
        XCTAssertFalse(store.hasAccess)
    }

    func testAccountMonthlyPlanCountsOnlyWithinItsPeriod() async {
        let recorder = FakeRecorder()
        recorder.owned = [AccountEntitlement(productID: .monthly, purchasedAt: start.addingTimeInterval(-40 * 86_400),
                                             expiresAt: start.addingTimeInterval(86_400), revoked: false)]
        let store = makeStore()
        await store.connectServer(recorder)
        XCTAssertTrue(store.hasAccess)
        XCTAssertTrue(store.hasActiveSubscription)

        recorder.owned = [AccountEntitlement(productID: .monthly, purchasedAt: start.addingTimeInterval(-40 * 86_400),
                                             expiresAt: start.addingTimeInterval(-1), revoked: false)]
        let lapsed = makeStore()
        await lapsed.connectServer(recorder)
        XCTAssertFalse(lapsed.hasAccess)
    }

    func testFreePlanClaimedWithTheAccountFollowsItsSevenDays() async {
        let recorder = FakeRecorder()
        let claimed = start.addingTimeInterval(-2 * 86_400)
        recorder.owned = [AccountEntitlement(productID: .earlyAdopter, purchasedAt: claimed, expiresAt: nil, revoked: false)]
        let store = makeStore()
        await store.connectServer(recorder)
        XCTAssertTrue(store.hasAccess, "Within the seven days")

        let later = makeStore(now: { claimed.addingTimeInterval(30 * 86_400) })
        await later.connectServer(recorder)
        XCTAssertFalse(later.hasAccess, "Unfinished after seven days")
        XCTAssertFalse(later.canOfferEarlyAccess, "The free plan is one per account, on any device")
        later.updateCompletion(claimed.addingTimeInterval(3 * 86_400))
        XCTAssertTrue(later.hasAccess, "Finished in time: free forever")
    }

    // MARK: - Monthly plan and the subscriber offer

    func testMonthlyPlanUnlocksAndHalfPriceLifetimeNeedsIt() async {
        let purchasing = FakePurchases()
        let store = makeStore(purchasing: purchasing)
        await store.start()
        let early = await store.continueWith(.subscriberLifetime)
        XCTAssertFalse(early, "Half price is for subscribers only")
        XCTAssertTrue(purchasing.purchaseCalls.isEmpty)

        purchasing.result = .purchased(monthly(until: start.addingTimeInterval(30 * 86_400)))
        let subscribed = await store.continueWith(.monthly)
        XCTAssertTrue(subscribed)
        XCTAssertTrue(store.hasActiveSubscription)
        XCTAssertTrue(store.offersSubscriberLifetime)

        purchasing.result = .purchased(LifetimeStoreTransaction(productID: .subscriberLifetime, originalID: "half",
                                                                originalPurchaseDate: start))
        let bought = await store.continueWith(.subscriberLifetime)
        XCTAssertTrue(bought)
        XCTAssertEqual(purchasing.purchaseCalls, [.monthly, .subscriberLifetime], "A subscriber really buys it")
        XCTAssertTrue(store.hasLifetimeAccess)
        XCTAssertFalse(store.offersSubscriberLifetime)
        XCTAssertTrue(store.asksToCancelSubscription, "Apple keeps billing the monthly plan unless they cancel it")
    }

    func testLifetimeBuyersAreAskedToCancelUntilThePlanStopsRenewing() async {
        let purchasing = FakePurchases()
        let half = LifetimeStoreTransaction(productID: .subscriberLifetime, originalID: "half", originalPurchaseDate: start)
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400)), half])
        purchasing.willRenew = true
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertTrue(store.remindsToCancelSubscription, "Apple keeps charging: keep asking")
        XCTAssertFalse(store.offersSubscriberLifetime)

        purchasing.willRenew = false
        await store.refresh()
        XCTAssertFalse(store.remindsToCancelSubscription, "Cancelled: the rest of the month is just used up")
        XCTAssertTrue(store.hasAccess)

        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400))])
        purchasing.willRenew = true
        await store.refresh()
        XCTAssertFalse(store.remindsToCancelSubscription, "Only someone with lifetime access is asked to cancel")
    }

    func testFromMonthlyToLifetimeUntilThePlanIsCancelled() async {
        let purchasing = FakePurchases()
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400))])
        purchasing.willRenew = true
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertTrue(store.offersSubscriberLifetime)
        XCTAssertFalse(store.remindsToCancelSubscription, "No lifetime access yet: nothing to cancel")

        let half = LifetimeStoreTransaction(productID: .subscriberLifetime, originalID: "half", originalPurchaseDate: start)
        purchasing.result = .purchased(half)
        let bought = await store.continueWith(.subscriberLifetime)
        XCTAssertTrue(bought)
        XCTAssertTrue(store.asksToCancelSubscription, "Asked right away")
        XCTAssertFalse(store.offersSubscriberLifetime, "The offer is gone")
        XCTAssertEqual(store.subscriptionToCancel, .appStore)
        XCTAssertFalse(store.cancelsOnAnotherAppleID)

        // Ignoring the question keeps the card: Apple keeps charging.
        store.asksToCancelSubscription = false
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400)), half])
        await store.refresh()
        XCTAssertTrue(store.remindsToCancelSubscription)

        await store.manageSubscription()
        XCTAssertEqual(purchasing.managed, [.appStore], "Apple's own page opens")
        XCTAssertFalse(store.remindsToCancelSubscription, "Cancelled: no more asking")
        XCTAssertTrue(store.hasAccess)

        // The paid month runs out; lifetime access stays.
        let later = makeStore(purchasing: purchasing, now: { self.start.addingTimeInterval(40 * 86_400) })
        purchasing.state = LifetimeStoreSnapshot(entitlements: [half])
        await later.start()
        XCTAssertTrue(later.hasAccess)
        XCTAssertFalse(later.remindsToCancelSubscription)
        XCTAssertFalse(later.offersSubscriberLifetime)
    }

    func testAPlanBilledElsewhereIsCancelledWhereItIsBilled() async {
        let lifetime = LifetimeStoreTransaction(productID: .lifetime, originalID: "life", originalPurchaseDate: start)
        func plan(_ store: String, renews: Bool?) -> AccountEntitlement {
            AccountEntitlement(productID: .monthly, purchasedAt: start, expiresAt: start.addingTimeInterval(10 * 86_400),
                               revoked: false, store: store, autoRenews: renews)
        }
        let purchasing = FakePurchases()
        purchasing.state = LifetimeStoreSnapshot(entitlements: [lifetime])
        let recorder = FakeRecorder()

        recorder.owned = [plan("app_store", renews: true)]
        let otherAppleID = makeStore(purchasing: purchasing)
        await otherAppleID.start()
        await otherAppleID.connectServer(recorder)
        XCTAssertEqual(otherAppleID.subscriptionToCancel, .appStore)
        XCTAssertTrue(otherAppleID.cancelsOnAnotherAppleID, "This phone can't open that Apple ID's plan")

        recorder.owned = [plan("play", renews: true)]
        let android = makeStore(purchasing: purchasing)
        await android.start()
        await android.connectServer(recorder)
        XCTAssertEqual(android.subscriptionToCancel, .googlePlay)
        XCTAssertFalse(android.cancelsOnAnotherAppleID)
        await android.manageSubscription()
        XCTAssertEqual(purchasing.managed, [.googlePlay], "Google Play's page opens")

        for renews in [false, nil] as [Bool?] {
            recorder.owned = [plan("app_store", renews: renews)]
            let settled = makeStore(purchasing: purchasing)
            await settled.start()
            await settled.connectServer(recorder)
            XCTAssertFalse(settled.remindsToCancelSubscription, "Cancelled, or not known: don't nag")
        }
    }

    func testThisAppleIDsAnswerBeatsTheServersOlderCopy() async {
        let purchasing = FakePurchases()
        let half = LifetimeStoreTransaction(productID: .subscriberLifetime, originalID: "half", originalPurchaseDate: start)
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(20 * 86_400)), half])
        purchasing.willRenew = false
        let recorder = FakeRecorder()
        recorder.owned = [AccountEntitlement(productID: .monthly, purchasedAt: start,
                                             expiresAt: start.addingTimeInterval(20 * 86_400), revoked: false,
                                             store: "app_store", autoRenews: true)]
        let store = makeStore(purchasing: purchasing)
        await store.start()
        await store.connectServer(recorder)
        XCTAssertFalse(store.remindsToCancelSubscription, "Just cancelled here; the server hears it on the next sync")
    }

    func testACancelledPlanEndsAccessByItselfAndOffersThePlansAgain() async throws {
        // Real time: the store wakes itself up when the paid month ends.
        let purchasing = FakePurchases()
        let early = transaction(at: Date().addingTimeInterval(-10 * 86_400))
        let plan = LifetimeStoreTransaction(productID: .monthly, originalID: "sub", originalPurchaseDate: Date(),
                                            expiresAt: Date().addingTimeInterval(1))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early, plan], firstEarlyPurchase: early)
        let store = makeStore(purchasing: purchasing, now: { Date() })
        await store.start()
        XCTAssertTrue(store.hasAccess)
        XCTAssertFalse(store.canOfferEarlyAccess)

        // Cancelled: StoreKit no longer lists it once the period is over.
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
        try await Task.sleep(for: .seconds(2.5))
        XCTAssertFalse(store.hasAccess, "No tap needed: access ends with the paid month")
        XCTAssertFalse(store.canOfferEarlyAccess, "The plans come back with monthly, not the free plan")
        XCTAssertFalse(store.remindsToCancelSubscription)
        XCTAssertFalse(store.offersSubscriberLifetime)
    }

    func testLapsedAccessScreenRenders() async throws {
        let purchasing = FakePurchases()
        let early = transaction(at: start.addingTimeInterval(-40 * 86_400))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertFalse(store.hasAccess)
        for (name, language) in [("lapsed-en", AppLanguage.english), ("lapsed-nl", AppLanguage.dutch)] {
            AppLanguageSettings.shared.language = language
            defer { AppLanguageSettings.shared.language = .english }
            let screen = EarlyAccessView(access: store, onContinue: {}, onBack: {}, profileIsComplete: true)
                .environment(\.locale, language.locale)
            try await render(screen, name: name, width: 393, height: 852)
        }
    }

    func testMonthlyIsOfferedOnlyOnceTheFreePlanIsGone() async {
        // The access screen shows the free plan or the monthly plan, never both.
        let fresh = makeStore()
        await fresh.start()
        XCTAssertTrue(fresh.canOfferEarlyAccess, "New: free plan, so no monthly plan")

        let purchasing = FakePurchases()
        let early = transaction(at: start.addingTimeInterval(-3 * 86_400))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [early], firstEarlyPurchase: early)
        let running = makeStore(purchasing: purchasing)
        await running.start()
        XCTAssertTrue(running.canOfferEarlyAccess, "Within the seven days: still the free plan")

        let old = transaction(at: start.addingTimeInterval(-8 * 86_400))
        purchasing.state = LifetimeStoreSnapshot(entitlements: [old], firstEarlyPurchase: old)
        let expired = makeStore(purchasing: purchasing)
        await expired.start()
        XCTAssertFalse(expired.canOfferEarlyAccess, "After seven days: the monthly plan instead")
        expired.revealEarlyAccess()
        XCTAssertTrue(expired.canOfferEarlyAccess, "The hidden hold brings the free plan back, and hides monthly")
    }

    func testClosedOfferReturnsAMonthLater() async {
        let purchasing = FakePurchases()
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(400 * 86_400))])
        let defaults = freshDefaults()
        var now = start
        let store = makeStore(purchasing: purchasing, defaults: defaults, now: { now })
        await store.start()
        XCTAssertTrue(store.offersSubscriberLifetime)
        store.dismissSubscriberOffer()
        XCTAssertFalse(store.offersSubscriberLifetime)
        XCTAssertFalse(makeStore(purchasing: purchasing, defaults: defaults).offersSubscriberLifetime,
                       "Closing it is remembered")

        now = Calendar.current.date(byAdding: .day, value: 20, to: start)!
        await store.refresh()
        XCTAssertFalse(store.offersSubscriberLifetime)
        now = Calendar.current.date(byAdding: .month, value: 1, to: start)!
        await store.refresh()
        XCTAssertTrue(store.offersSubscriberLifetime)
    }

    func testExpiredMonthlyPlanLosesAccess() async {
        let purchasing = FakePurchases()
        purchasing.state = LifetimeStoreSnapshot(entitlements: [monthly(until: start.addingTimeInterval(-1))])
        let store = makeStore(purchasing: purchasing)
        await store.start()
        XCTAssertFalse(store.hasAccess)
        XCTAssertFalse(store.offersSubscriberLifetime)
    }
}

@MainActor
private final class FakeLedgerStore: EarlyAccessLedgerStoring {
    var ledger = EarlyAccessLedger()
    var fails = false
    func load() throws -> EarlyAccessLedger { ledger }
    func save(_ ledger: EarlyAccessLedger) throws {
        if fails { throw NSError(domain: "test", code: 1) }
        self.ledger = ledger
    }
}

@MainActor
private final class FakeReminder: EarlyAccessReminderScheduling {
    var permission = true
    var permissionRequests = 0
    var scheduled: [Date] = []
    func requestPermission() async throws -> Bool { permissionRequests += 1; return permission }
    func schedule(at date: Date, now: Date) async throws { scheduled.append(date) }
    func cancel() { scheduled.removeAll() }
}

@MainActor
private final class FakePurchases: LifetimePurchasing {
    var state = LifetimeStoreSnapshot()
    var result = LifetimePurchaseResult.cancelled
    var purchaseCalls: [LifetimeProductID] = []
    var finished = 0
    var willRenew = false
    var managed: [SubscriptionStore] = []
    func monthlyWillRenew() async -> Bool { willRenew }
    /// Apple's sheet, where the person cancels.
    func manageSubscriptions(in store: SubscriptionStore) async {
        managed.append(store)
        willRenew = false
    }
    func products() async throws -> [LifetimeStoreProduct] {
        [.init(id: .earlyAdopter, displayPrice: "US$0.00"), .init(id: .lifetime, displayPrice: "US$54.99"),
         .init(id: .monthly, displayPrice: "US$0.99"), .init(id: .subscriberLifetime, displayPrice: "US$27.49")]
    }
    func snapshot() async -> LifetimeStoreSnapshot { state }
    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult { purchaseCalls.append(id); return result }
    func restore() async throws {}
    func finish(_ transaction: LifetimeStoreTransaction) async { finished += 1 }
}

@MainActor
private final class FakeRecorder: StoreEntitlementRecording {
    var owned: [AccountEntitlement] = []
    func record(appStoreTransactions: [String], appStoreRenewals: [String]) async throws {}
    func accountEntitlements() async throws -> [AccountEntitlement] { owned }
}
