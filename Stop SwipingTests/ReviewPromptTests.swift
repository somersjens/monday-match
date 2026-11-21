import XCTest
@testable import Stop_Swiping

/// The store's review sheet only follows a good moment, from someone who
/// knows the app, never right after something bad and never twice in one
/// version or within four months.
@MainActor
final class ReviewPromptTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let midnight = calendar.startOfDay(for: start)
        return calendar.date(byAdding: DateComponents(day: offset, hour: hour), to: midnight)!
    }

    /// Opened on three days, the first of them three days ago, one good moment.
    private func eligibleLedger() -> ReviewPromptLedger {
        var ledger = ReviewPromptLedger()
        for offset in [0, 1, 3] { ledger.recordOpen(now: day(offset), calendar: calendar) }
        ledger.record(.inPersonMatch, matchID: UUID())
        return ledger
    }

    func testEligibleAfterAFewDaysOfUseAndAGoodMoment() {
        XCTAssertTrue(eligibleLedger().mayAsk(now: day(3), appVersion: "1.0", calendar: calendar))
    }

    func testNotWithoutAGoodMoment() {
        var ledger = ReviewPromptLedger()
        for offset in [0, 1, 3] { ledger.recordOpen(now: day(offset), calendar: calendar) }
        XCTAssertFalse(ledger.mayAsk(now: day(3), appVersion: "1.0", calendar: calendar))
    }

    func testNotInTheFirstDays() {
        var ledger = ReviewPromptLedger()
        ledger.recordOpen(now: day(0, hour: 9), calendar: calendar)
        ledger.recordOpen(now: day(1), calendar: calendar)
        ledger.recordOpen(now: day(2), calendar: calendar)
        ledger.record(.inPersonMatch, matchID: UUID())
        XCTAssertFalse(ledger.mayAsk(now: day(2), appVersion: "1.0", calendar: calendar), "Only two days since first use.")
    }

    func testOpeningTwiceOnOneDayCountsOnce() {
        var ledger = ReviewPromptLedger()
        for hour in [8, 12, 20] { ledger.recordOpen(now: day(0, hour: hour), calendar: calendar) }
        ledger.recordOpen(now: day(5), calendar: calendar)
        ledger.record(.conversation, matchID: UUID())
        XCTAssertFalse(ledger.mayAsk(now: day(5), appVersion: "1.0", calendar: calendar), "Two active days, not three.")
    }

    func testASetbackKeepsItAwayForAWeek() {
        var ledger = eligibleLedger()
        ledger.record(.noMatch, now: day(2))
        XCTAssertFalse(ledger.mayAsk(now: day(3), appVersion: "1.0", calendar: calendar))
        XCTAssertFalse(ledger.mayAsk(now: day(8), appVersion: "1.0", calendar: calendar))
        XCTAssertTrue(ledger.mayAsk(now: day(9), appVersion: "1.0", calendar: calendar))
    }

    func testNeverTwiceInOneVersionAndFourMonthsApart() {
        var ledger = eligibleLedger()
        ledger.markAsked(now: day(3), appVersion: "1.0")
        XCTAssertFalse(ledger.mayAsk(now: day(300), appVersion: "1.0", calendar: calendar), "Same version.")
        XCTAssertFalse(ledger.mayAsk(now: day(100), appVersion: "1.1", calendar: calendar), "Too soon.")
        XCTAssertTrue(ledger.mayAsk(now: day(123), appVersion: "1.1", calendar: calendar))
    }

    func testTheSameMatchCountsOnce() {
        var ledger = ReviewPromptLedger()
        let id = UUID()
        XCTAssertTrue(ledger.record(.conversation, matchID: id))
        XCTAssertFalse(ledger.record(.conversation, matchID: id))
        XCTAssertEqual(ledger.positiveMoments, 1)
    }

    func testARealConversationNeedsBothPeople() {
        let mine = (0..<3).map { _ in ChatMessage(sender: .currentUser, text: "Hi") }
        let theirs = (0..<3).map { _ in ChatMessage(sender: .match, text: "Hey") }
        XCTAssertFalse(ReviewMoment.isRealConversation(mine + [ChatMessage(sender: .system, text: "x")]))
        XCTAssertFalse(ReviewMoment.isRealConversation(mine + theirs.dropLast()))
        XCTAssertTrue(ReviewMoment.isRealConversation(mine + theirs))
    }

    // MARK: Center

    private final class Requests: ReviewRequesting {
        var count = 0
        func requestReview() { count += 1 }
    }

    private func center(now: @escaping () -> Date, requests: Requests, defaults: UserDefaults,
                        version: String = "1.0") -> ReviewPromptCenter {
        ReviewPromptCenter(defaults: defaults, requester: requests, appVersion: version, now: now, isEnabled: true)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ReviewPromptTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testCenterAsksOnceForAGoodMomentAndRemembersIt() {
        let defaults = freshDefaults()
        let requests = Requests()
        var now = day(0)
        let center = center(now: { now }, requests: requests, defaults: defaults)
        for offset in [0, 1, 3] {
            now = day(offset)
            center.recordOpen()
        }
        let first = UUID()
        XCTAssertFalse(center.askIfCalm(afterClosing: first), "Nothing good happened yet.")
        center.record(.inPersonMatch, matchID: first)
        XCTAssertTrue(center.askIfCalm(afterClosing: first))
        XCTAssertEqual(requests.count, 1)

        let second = UUID()
        center.record(.inPersonMatch, matchID: second)
        XCTAssertFalse(center.askIfCalm(afterClosing: second), "Already asked in this version.")

        let reopened = self.center(now: { now }, requests: requests, defaults: defaults)
        XCTAssertEqual(reopened.ledger.lastAskedVersion, "1.0", "The ledger survives a relaunch.")
        XCTAssertEqual(requests.count, 1)
    }

    func testASetbackOrALeftScreenDropsThePendingMoment() {
        let defaults = freshDefaults()
        let requests = Requests()
        var now = day(0)
        let center = center(now: { now }, requests: requests, defaults: defaults)
        for offset in [0, 1, 3] {
            now = day(offset)
            center.recordOpen()
        }
        let scanned = UUID()
        center.record(.inPersonMatch, matchID: scanned)
        center.discardPendingMoment()
        XCTAssertFalse(center.askIfCalm(afterClosing: scanned))

        let other = UUID()
        center.record(.inPersonMatch, matchID: other)
        XCTAssertFalse(center.askIfCalm(afterClosing: UUID()), "Another match closed: the moment passed.")
        XCTAssertNil(center.pendingMoment)
        XCTAssertFalse(center.askIfCalm(afterClosing: other))

        now = day(20)
        let chat = UUID()
        center.record(.conversation, matchID: chat)
        center.record(.reportSent)
        XCTAssertNil(center.pendingMoment)
        XCTAssertFalse(center.askIfCalm(afterClosing: chat))
        XCTAssertEqual(requests.count, 0)
    }

    func testStoreLinks() {
        XCTAssertEqual(StoreListing.reviewURL(for: .appStore)?.absoluteString,
                       "https://apps.apple.com/app/id6830641479?action=write-review")
        XCTAssertNil(StoreListing.reviewURL(for: .googlePlay), "No package name until the Play listing exists.")
    }
}
