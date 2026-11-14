import SwiftUI
import UIKit
import XCTest
@testable import Stop_Swiping

@MainActor
final class LifetimeAccessTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_491_200)

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
                                             now: { self.start.addingTimeInterval(30 * 86_400) })
        await relaunched.start()
        XCTAssertTrue(relaunched.hasAccess)
    }

    func testAccessScreenRendersInBothLanguagesAndAfterExpiry() async throws {
        for (name, language, expired, width, height) in [
            ("early-en", AppLanguage.english, false, 393.0, 852.0),
            ("early-nl", AppLanguage.dutch, false, 393.0, 852.0),
            ("expired", AppLanguage.english, true, 393.0, 852.0),
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
    }

    private func transaction(at date: Date) -> LifetimeStoreTransaction {
        LifetimeStoreTransaction(productID: .earlyAdopter, originalID: "first", originalPurchaseDate: date)
    }

    private func makeStore(purchasing: FakePurchases? = nil, storage: FakeLedgerStore? = nil,
                           reminder: FakeReminder? = nil) -> LifetimeAccessStore {
        LifetimeAccessStore(purchasing: purchasing ?? FakePurchases(), storage: storage ?? FakeLedgerStore(), reminder: reminder ?? FakeReminder(), now: { self.start })
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
    func products() async throws -> [LifetimeStoreProduct] {
        [.init(id: .earlyAdopter, displayPrice: "US$0.00"), .init(id: .lifetime, displayPrice: "US$54.99")]
    }
    func snapshot() async -> LifetimeStoreSnapshot { state }
    func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult { purchaseCalls.append(id); return result }
    func restore() async throws {}
    func finish(_ transaction: LifetimeStoreTransaction) async { finished += 1 }
}
