import Foundation
import StoreKit
import UIKit

/// A moment someone is plainly glad about, right after it happened. Only
/// these may lead to the store's review request.
enum ReviewMoment: String, Codable, Equatable {
    /// A new match with someone in person (a scanned code or two phones
    /// together), not a repeat of an earlier comparison.
    case inPersonMatch = "in_person_match"
    /// An automatic match that turned into a real conversation: both people
    /// wrote several messages and the match is still on.
    case conversation

    /// Both people wrote at least this many messages.
    static let conversationMessagesEach = 3

    static func isRealConversation(_ messages: [ChatMessage]) -> Bool {
        messages.filter { $0.sender == .currentUser }.count >= conversationMessagesEach
            && messages.filter { $0.sender == .match }.count >= conversationMessagesEach
    }
}

/// Something that went wrong or felt bad. For a while after one, the app
/// never asks for a review, however good the next moment is.
enum ReviewSetback: String, Codable, Equatable {
    case noMatch = "no_match"
    case matchEnded = "match_ended"
    case reportSent = "report_sent"
    case moderationNotice = "moderation_notice"
}

/// Everything the app remembers about asking for a review, kept on this
/// phone only. Plain Swift, so the Android app (Skip) shares the rules.
///
/// Apple and Google both decide themselves whether their review sheet
/// appears (Apple at most three times a year, Google on an undisclosed
/// quota) and neither tells the app. So the app asks rarely and only at a
/// good moment, and never asks its own "Do you like the app?" first: both
/// stores forbid steering unhappy people away from the review sheet.
struct ReviewPromptLedger: Codable, Equatable {
    var firstSeen: Date?
    /// Calendar days the app was opened on, newest last, at most `activeDayLimit`.
    private(set) var activeDays: [String] = []
    private(set) var positiveMoments = 0
    /// Matches that already counted, so reopening one isn't a new moment.
    private(set) var countedMatches: [UUID] = []
    var lastSetback: Date?
    var lastAsked: Date?
    var lastAskedVersion: String?
    private(set) var timesAsked = 0

    /// Someone needs to know the app a little: a few days, on a few of them.
    static let minimumDaysSinceFirstUse = 3
    static let minimumActiveDays = 3
    /// After something bad, a good moment soon after isn't asked about.
    static let setbackQuietDays = 7
    /// Never more often than this, and never twice in one version.
    static let minimumDaysBetweenAsks = 120
    static let activeDayLimit = 30
    static let countedMatchLimit = 50

    mutating func recordOpen(now: Date, calendar: Calendar = .current) {
        if firstSeen == nil { firstSeen = now }
        let day = Self.dayKey(now, calendar: calendar)
        guard activeDays.last != day else { return }
        activeDays.append(day)
        if activeDays.count > Self.activeDayLimit { activeDays.removeFirst(activeDays.count - Self.activeDayLimit) }
    }

    /// Returns false when this match already counted.
    @discardableResult
    mutating func record(_ moment: ReviewMoment, matchID: UUID) -> Bool {
        guard !countedMatches.contains(matchID) else { return false }
        countedMatches.append(matchID)
        if countedMatches.count > Self.countedMatchLimit {
            countedMatches.removeFirst(countedMatches.count - Self.countedMatchLimit)
        }
        positiveMoments += 1
        return true
    }

    mutating func record(_ setback: ReviewSetback, now: Date) {
        lastSetback = now
    }

    /// Whether a good moment that just happened may lead to the review request.
    func mayAsk(now: Date, appVersion: String, calendar: Calendar = .current) -> Bool {
        guard positiveMoments > 0, let firstSeen,
              Self.days(from: firstSeen, to: now, calendar: calendar) >= Self.minimumDaysSinceFirstUse,
              activeDays.count >= Self.minimumActiveDays else { return false }
        if let lastSetback, Self.days(from: lastSetback, to: now, calendar: calendar) < Self.setbackQuietDays {
            return false
        }
        if lastAskedVersion == appVersion { return false }
        if let lastAsked, Self.days(from: lastAsked, to: now, calendar: calendar) < Self.minimumDaysBetweenAsks {
            return false
        }
        return true
    }

    mutating func markAsked(now: Date, appVersion: String) {
        lastAsked = now
        lastAskedVersion = appVersion
        timesAsked += 1
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// Shows the store's own review sheet. iOS: StoreKit. Android: Google
/// Play's In-App Review API (see docs/app-reviews.md).
@MainActor
protocol ReviewRequesting {
    func requestReview()
}

@MainActor
struct StoreReviewRequester: ReviewRequesting {
    /// Nonisolated, so it can be the default argument of `ReviewPromptCenter.init`.
    nonisolated init() {}

    func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }
}

/// Collects good moments and setbacks and asks for a review only when the
/// ledger allows it and the screen is calm.
@MainActor
final class ReviewPromptCenter {
    static let shared = ReviewPromptCenter()

    private(set) var ledger: ReviewPromptLedger
    /// The good moment waiting for the screen to settle, and its match.
    private(set) var pendingMoment: ReviewMoment?
    private var pendingMatchID: UUID?
    private let defaults: UserDefaults
    private let requester: ReviewRequesting
    private let appVersion: String
    private let now: () -> Date
    /// Off inside unit and UI tests, so a test run never shows the sheet.
    private let isEnabled: Bool
    static let storageKey = "reviewPrompt.ledger.v1"

    init(defaults: UserDefaults = .standard, requester: ReviewRequesting = StoreReviewRequester(),
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
         now: @escaping () -> Date = Date.init, isEnabled: Bool = !ReviewPromptCenter.isRunningTests) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        self.requester = requester
        self.appVersion = appVersion
        self.now = now
        ledger = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(ReviewPromptLedger.self, from: $0) } ?? ReviewPromptLedger()
    }

    func recordOpen() {
        ledger.recordOpen(now: now())
        save()
    }

    /// Remembers the moment; the request itself waits for `askIfCalm`.
    func record(_ moment: ReviewMoment, matchID: UUID) {
        guard ledger.record(moment, matchID: matchID) else { return }
        pendingMoment = moment
        pendingMatchID = matchID
        save()
    }

    func record(_ setback: ReviewSetback) {
        ledger.record(setback, now: now())
        discardPendingMoment()
        save()
    }

    /// Called once the home screen is quiet again after the match with the
    /// good moment closed, with nothing else on it. Any other match closing
    /// lets the moment pass. Returns whether the store was asked.
    @discardableResult
    func askIfCalm(afterClosing matchID: UUID) -> Bool {
        guard pendingMoment != nil, pendingMatchID == matchID else {
            discardPendingMoment()
            return false
        }
        discardPendingMoment()
        guard isEnabled, ledger.mayAsk(now: now(), appVersion: appVersion) else { return false }
        ledger.markAsked(now: now(), appVersion: appVersion)
        save()
        requester.requestReview()
        return true
    }

    /// The moment passed without a calm screen (the app went away, another
    /// screen opened): it isn't asked about later, out of context.
    func discardPendingMoment() {
        pendingMoment = nil
        pendingMatchID = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    nonisolated static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
