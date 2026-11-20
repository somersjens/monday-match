import XCTest
@testable import Stop_Swiping

/// Lifetime access is sent to the server only when something changed.
@MainActor
final class StoreEntitlementSyncTests: XCTestCase {
    private final class Purchases: LifetimePurchasing {
        var signed: [SignedStoreTransaction] = []
        func products() async throws -> [LifetimeStoreProduct] { [] }
        func snapshot() async -> LifetimeStoreSnapshot { LifetimeStoreSnapshot() }
        func purchase(_ id: LifetimeProductID) async throws -> LifetimePurchaseResult { .cancelled }
        func restore() async throws {}
        func finish(_ transaction: LifetimeStoreTransaction) async {}
        func signedTransactions() async -> [SignedStoreTransaction] { signed }
    }

    private final class Recorder: StoreEntitlementRecording {
        var calls: [[String]] = []
        var renewals: [[String]] = []
        var fails = false
        var account: String? = "account-1"
        func accountID() async -> String? { account }
        func record(appStoreTransactions: [String], appStoreRenewals: [String]) async throws {
            if fails { throw URLError(.notConnectedToInternet) }
            calls.append(appStoreTransactions)
            renewals.append(appStoreRenewals)
        }
    }

    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "StoreEntitlementSyncTests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSendsOnceAndAgainOnlyAfterAChange() async {
        let purchases = Purchases(), recorder = Recorder()
        let sync = StoreEntitlementSync(recorder: recorder, purchasing: purchases, defaults: defaults)
        await sync.syncIfNeeded()
        XCTAssertTrue(recorder.calls.isEmpty, "Nothing bought, nothing sent")

        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "a.b.c")]
        await sync.syncIfNeeded()
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls, [["a.b.c"]])

        purchases.signed = [.init(originalID: "1", isRevoked: true, jws: "a.b.d")]
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls.last, ["a.b.d"], "A refund is sent too")
    }

    func testANewAccountOnThisPhoneGetsThePurchaseToo() async {
        let purchases = Purchases(), recorder = Recorder()
        let sync = StoreEntitlementSync(recorder: recorder, purchasing: purchases, defaults: defaults)
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "a.b.c")]
        await sync.syncIfNeeded()
        recorder.account = "account-2"
        await sync.syncIfNeeded()
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls, [["a.b.c"], ["a.b.c"]],
                       "Recorded for one account, sent once more for the next (seen 20 November 2026)")
    }

    func testARenewalIsSentAgain() async {
        let purchases = Purchases(), recorder = Recorder()
        let sync = StoreEntitlementSync(recorder: recorder, purchasing: purchases, defaults: defaults)
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "m.1", expiresAt: Date(timeIntervalSince1970: 100))]
        await sync.syncIfNeeded()
        await sync.syncIfNeeded()
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "m.2", expiresAt: Date(timeIntervalSince1970: 200))]
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls, [["m.1"], ["m.2"]], "Same original ID, a later period")
    }

    func testCancellingThePlanIsSentSoOtherDevicesStopAsking() async {
        let purchases = Purchases(), recorder = Recorder()
        let sync = StoreEntitlementSync(recorder: recorder, purchasing: purchases, defaults: defaults)
        let end = Date(timeIntervalSince1970: 100)
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "m.1", expiresAt: end,
                                  renewalJWS: "r.on", willAutoRenew: true)]
        let first = await sync.syncIfNeeded()
        XCTAssertTrue(first)
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "m.1", expiresAt: end,
                                  renewalJWS: "r.off", willAutoRenew: false)]
        let cancelled = await sync.syncIfNeeded()
        XCTAssertTrue(cancelled, "Same period, but it no longer renews")
        let again = await sync.syncIfNeeded()
        XCTAssertFalse(again)
        XCTAssertEqual(recorder.renewals, [["r.on"], ["r.off"]])
    }

    func testAFailedSendIsRetriedAndSignOutStartsOver() async {
        let purchases = Purchases(), recorder = Recorder()
        purchases.signed = [.init(originalID: "1", isRevoked: false, jws: "a.b.c")]
        let sync = StoreEntitlementSync(recorder: recorder, purchasing: purchases, defaults: defaults)
        recorder.fails = true
        await sync.syncIfNeeded()
        recorder.fails = false
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls.count, 1)

        sync.accountSignedOut()
        await sync.syncIfNeeded()
        XCTAssertEqual(recorder.calls.count, 2, "The next account records the purchase for itself")
    }
}
